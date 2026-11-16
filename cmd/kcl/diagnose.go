package main

import (
	"crypto/sha256"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"sync"
)

var functionLabel = regexp.MustCompile(`^\S.*:$`)
var addressLabel = regexp.MustCompile(`^\s*[0-9a-fA-F]+:`)
var flagMove = regexp.MustCompile(`\bmov[lq]?\s+\$(0x[0-9a-fA-F]+|[0-9]+),\s*%[er]dx\b`)

func analyze(disassembly string) map[string]any {
	var functions [][]string
	current := -1
	for _, line := range strings.Split(disassembly, "\n") {
		if functionLabel.MatchString(line) && !addressLabel.MatchString(line) {
			current = -1
			if strings.Contains(line, "CreatePrivateKey") {
				functions = append(functions, nil)
				current = len(functions) - 1
			}
		} else if current >= 0 {
			functions[current] = append(functions[current], line)
		}
	}
	var values []uint64
	for _, lines := range functions {
		for i, line := range lines {
			m := flagMove.FindStringSubmatch(line)
			if m == nil {
				continue
			}
			for j := i + 1; j < len(lines) && j < i+5; j++ {
				if strings.Contains(lines[j], "SecAccessControlCreateWithFlags") {
					base := 10
					s := m[1]
					if strings.HasPrefix(s, "0x") {
						base = 16
						s = s[2:]
					}
					v, e := strconv.ParseUint(s, base, 64)
					if e == nil {
						values = append(values, v)
					}
					break
				}
			}
		}
	}
	status := "unknown"
	if len(values) > 1 {
		status = "ambiguous"
	}
	report := map[string]any{"status": status, "acl_call_sites": len(values)}
	if len(values) == 1 {
		status = "unknown_constraint"
		if values[0] == 0x40000000 {
			status = "known_private_key_usage_constraint"
		} else if values[0] == 0 {
			status = "zero_constraint_observed_not_proof_of_fix"
		}
		report["status"] = status
		report["flags"] = fmt.Sprintf("0x%x", values[0])
	}
	return report
}
func diagnosticSelfTest() error {
	call := "\n00000001 callq _SecAccessControlCreateWithFlags\n"
	scope := "__CreatePrivateKey:\n"
	broken := scope + "00000000 movl $0x40000000, %edx" + call
	cases := []struct{ s, want string }{{broken, "known_private_key_usage_constraint"}, {"__OtherFunction:\n00000000 movl $0, %edx" + call, "unknown"}, {scope + "00000000 movl $0, %edx" + call, "zero_constraint_observed_not_proof_of_fix"}, {broken + broken, "ambiguous"}, {scope + "00000000 movl $0, %edx\n00000001 callq _Unrelated\n", "unknown"}}
	for _, c := range cases {
		if analyze(c.s)["status"] != c.want {
			return errors.New("scoped ACL parser self-test failed")
		}
	}
	return nil
}
func diagnoseCommand(args []string) error {
	f := flag.NewFlagSet("diagnose", flag.ContinueOnError)
	app := f.String("app", "", "Explicit Codex app path (no fallback)")
	self := f.Bool("self-test", false, "Check scoped ACL parser without reading an app")
	if e := f.Parse(args); e != nil {
		return e
	}
	if f.NArg() != 0 {
		return errors.New("unexpected diagnose arguments")
	}
	if *self {
		if e := diagnosticSelfTest(); e != nil {
			return e
		}
		fmt.Println("Scoped ACL parser: PASS")
		return nil
	}
	candidates := []string{"/Applications/ChatGPT.app", "/Applications/Codex.app", join(home, "Applications/ChatGPT.app"), join(home, "Applications/Codex.app")}
	if *app != "" {
		p := *app
		if strings.HasPrefix(p, "~/") {
			p = join(home, p[2:])
		}
		candidates = []string{p}
	}
	target := ""
	for _, p := range candidates {
		if exists(join(p, modulePath)) {
			target = p
			break
		}
	}
	if target == "" {
		return errors.New("Codex app/native module not found")
	}
	info, e := readPlist(join(target, "Contents/Info.plist"))
	if e != nil {
		return e
	}
	if info["CFBundleIdentifier"] != "com.openai.codex" {
		return errors.New("unexpected app identifier")
	}
	module := join(target, modulePath)
	b, e := os.ReadFile(module)
	if e != nil {
		return e
	}
	before := sha256.Sum256(b)
	commands := [][]string{{"/usr/bin/codesign", "--verify", "--deep", "--strict", `-R=anchor apple generic and certificate leaf[subject.OU] = "2DC432GLL2" and identifier "com.openai.codex"`, target}, {"/usr/bin/codesign", "-dv", "--verbose=2", target}, {"/usr/bin/otool", "-tvV", module}, {"/usr/sbin/system_profiler", "SPiBridgeDataType"}}
	type result struct {
		text string
		ok   bool
	}
	results := make([]result, len(commands))
	var wg sync.WaitGroup
	for i, c := range commands {
		wg.Add(1)
		go func(i int, c []string) { defer wg.Done(); results[i].text, results[i].ok = capture(c...) }(i, c)
	}
	wg.Wait()
	var team, bridge any
	if m := regexp.MustCompile(`(?m)^TeamIdentifier=(.+)$`).FindStringSubmatch(results[1].text); m != nil {
		team = m[1]
	}
	if results[3].ok {
		bridge = strings.Contains(results[3].text, "T2")
	}
	native := map[string]any{"status": "unavailable"}
	if results[2].ok {
		native = analyze(results[2].text)
	}
	after, e := os.ReadFile(module)
	if e != nil {
		return e
	}
	arch := runtime.GOARCH
	if arch == "amd64" {
		arch = "x86_64"
	}
	report := map[string]any{"app": target, "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"], "architecture": arch, "vendor_signature_valid": results[0].ok, "team_id": team, "module_sha256": fmt.Sprintf("%x", before), "t2_bridge_reported": bridge, "native_analysis": native, "module_unchanged_during_diagnosis": before == sha256.Sum256(after)}
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	return enc.Encode(report)
}
