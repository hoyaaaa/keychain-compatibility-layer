package main

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestInstallerRollback(t *testing.T) {
	for _, scenario := range []string{"activation-failure", "success", "missing-staging", "first-install-failure"} {
		t.Run(scenario, func(t *testing.T) {
			dir := t.TempDir()
			staged, target, backup := join(dir, "staged"), join(dir, "target"), join(dir, "backup")
			previous := target
			if scenario != "missing-staging" {
				os.Mkdir(staged, 0755)
				os.WriteFile(join(staged, "version"), []byte("new"), 0600)
			}
			if scenario != "first-install-failure" {
				os.Mkdir(target, 0755)
				os.WriteFile(join(target, "version"), []byte("old"), 0600)
			} else {
				previous = ""
			}
			e := replaceBundle(staged, target, backup, previous, func() error {
				if scenario == "success" {
					return nil
				}
				return errors.New("simulated activation failure")
			})
			read := func(p string) string { b, _ := os.ReadFile(join(p, "version")); return string(b) }
			if scenario == "success" {
				if e != nil || read(target) != "new" || read(backup) != "old" {
					t.Fatal("success did not retain old bundle", e)
				}
				return
			}
			if e == nil {
				t.Fatal("expected error")
			}
			if scenario == "first-install-failure" {
				if exists(target) || read(staged) != "new" {
					t.Fatal("initial rollback failed")
				}
			} else if read(target) != "old" || exists(backup) {
				t.Fatal("old bundle not restored")
			}
		})
	}
}
func TestScopedDiagnostic(t *testing.T) {
	if e := diagnosticSelfTest(); e != nil {
		t.Fatal(e)
	}
}
func TestAgentValidation(t *testing.T) {
	target, legacy := "/Applications/KCL.app", "/Applications/Legacy.app"
	m := map[string]any{"Label": agentLabel, "ProgramArguments": []any{helperPath(target)}}
	if !validAgent(m, target, legacy) {
		t.Fatal("own agent rejected")
	}
	m["ProgramArguments"] = []any{"/bin/other"}
	if validAgent(m, target, legacy) {
		t.Fatal("foreign agent accepted")
	}
	m["ProgramArguments"] = []any{helperPath(legacy)}
	if !validAgent(m, target, legacy) {
		t.Fatal("legacy agent rejected")
	}
}
func TestPlistRoundtrip(t *testing.T) {
	p := filepath.Join(t.TempDir(), "agent.plist")
	m := map[string]any{"Label": agentLabel, "ProgramArguments": []any{"/a path/a&b"}, "RunAtLoad": true, "ThrottleInterval": float64(10)}
	if e := writePlist(p, m); e != nil {
		t.Fatal(e)
	}
	got, e := readPlist(p)
	if e != nil || !reflect.DeepEqual(got, m) {
		t.Fatal("plist changed", got, e)
	}
}
func TestAtomicWrite(t *testing.T) {
	p := join(t.TempDir(), "status.json")
	if e := atomicWrite(p, []byte("old"), 0600); e != nil {
		t.Fatal(e)
	}
	if e := atomicWrite(p, []byte("new"), 0600); e != nil {
		t.Fatal(e)
	}
	b, e := os.ReadFile(p)
	if e != nil || string(b) != "new" {
		t.Fatal("replacement failed", e)
	}
}
func TestInvalidCommands(t *testing.T) {
	for _, args := range [][]string{nil, {"unknown"}, {"build", "extra"}, {"install", "--wrong"}, {"diagnose", "--app", "/nonexistent-explicit.app"}} {
		if dispatch(args) == nil {
			t.Fatal("invalid command accepted", args)
		}
	}
}

func TestLegacyIdentityAcceptedOnlyForUpgrade(t *testing.T) {
	path := join(t.TempDir(), appName)
	if e := writePlist(join(path, "Contents/Info.plist"), map[string]any{"CFBundleIdentifier": legacyIdentifier}); e != nil {
		t.Fatal(e)
	}
	if e := requirePreviousID(path); e != nil {
		t.Fatal("legacy upgrade refused", e)
	}
	if requireID(path) == nil {
		t.Fatal("legacy source accepted as a new release")
	}
	if e := writePlist(join(path, "Contents/Info.plist"), map[string]any{"CFBundleIdentifier": "com.unrelated.app"}); e != nil {
		t.Fatal(e)
	}
	if requirePreviousID(path) == nil {
		t.Fatal("unrelated app accepted for replacement")
	}
}
