package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

var version = "dev"

const appName = "Keychain Compatibility Layer.app"
const identifier = "io.hoya.KeychainCompatibilityLayer"
const agentLabel = identifier + ".AutoApply"
const modulePath = "Contents/Resources/native/remote-control-device-key.node"
const lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

var home, _ = os.UserHomeDir()

func join(parts ...string) string { return filepath.Join(parts...) }
func exists(p string) bool        { _, e := os.Stat(p); return e == nil }
func run(args ...string) error {
	c := exec.Command(args[0], args[1:]...)
	c.Stdout = os.Stdout
	c.Stderr = os.Stderr
	return c.Run()
}
func capture(args ...string) (string, bool) {
	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
	defer cancel()
	b, e := exec.CommandContext(ctx, args[0], args[1:]...).CombinedOutput()
	return string(b), e == nil
}
func atomicWrite(path string, b []byte, mode os.FileMode) error {
	if e := os.MkdirAll(filepath.Dir(path), 0755); e != nil {
		return e
	}
	f, e := os.CreateTemp(filepath.Dir(path), ".kcl-*")
	if e != nil {
		return e
	}
	n := f.Name()
	defer os.Remove(n)
	if _, e = f.Write(b); e != nil {
		f.Close()
		return e
	}
	if e = f.Chmod(mode); e != nil {
		f.Close()
		return e
	}
	if e = f.Close(); e != nil {
		return e
	}
	return os.Rename(n, path)
}
func writePlist(path string, v map[string]any) error {
	b, e := json.Marshal(v)
	if e != nil {
		return e
	}
	c := exec.Command("/usr/bin/plutil", "-convert", "xml1", "-o", "-", "--", "-")
	c.Stdin = bytes.NewReader(b)
	out, e := c.Output()
	if e != nil {
		return fmt.Errorf("serialize plist: %w", e)
	}
	return atomicWrite(path, out, 0644)
}
func readPlist(path string) (map[string]any, error) {
	s, ok := capture("/usr/bin/plutil", "-convert", "json", "-o", "-", path)
	if !ok {
		return nil, fmt.Errorf("cannot read plist: %s", path)
	}
	var m map[string]any
	e := json.Unmarshal([]byte(s), &m)
	return m, e
}
func rootDir() (string, error) {
	if exists("VERSION") && exists("native/app/Host.m") {
		return os.Getwd()
	}
	exe, e := os.Executable()
	if e != nil {
		return "", e
	}
	p := filepath.Dir(exe)
	if exists(join(p, "VERSION")) && exists(join(p, "native/app/Host.m")) {
		return p, nil
	}
	return "", errors.New("run this command from the project source directory")
}
func main() {
	if version == "dev" {
		if root, e := rootDir(); e == nil {
			if b, e := os.ReadFile(join(root, "VERSION")); e == nil {
				version = strings.TrimSpace(string(b))
			}
		}
	}

	if e := dispatch(os.Args[1:]); e != nil {
		fmt.Fprintln(os.Stderr, e)
		os.Exit(1)
	}
}
func dispatch(args []string) error {
	if len(args) == 0 {
		return errors.New("usage: kcl version | build | install [--check] | install-auto | diagnose [--app PATH] [--self-test]")
	}
	switch args[0] {
	case "version", "--version":
		fmt.Println(strings.TrimSpace(version))
		return nil
	case "build":
		if len(args) != 1 {
			return errors.New("build takes no arguments")
		}
		r, e := rootDir()
		if e != nil {
			return e
		}
		return build(r)
	case "install":
		f := flag.NewFlagSet("install", flag.ContinueOnError)
		check := f.Bool("check", false, "Read-only preflight")
		source := f.String("source", "", "Signed KCL bundle to install")
		if e := f.Parse(args[1:]); e != nil {
			return e
		}
		if f.NArg() != 0 {
			return errors.New("unexpected install arguments")
		}
		if *source != "" {
			p, e := filepath.Abs(*source)
			if e != nil {
				return e
			}
			return install(p, *check)
		}
		r, e := rootDir()
		if e != nil {
			return e
		}
		return install(join(r, "build", appName), *check)
	case "dmg":
		if len(args) != 1 {
			return errors.New("dmg takes no arguments")
		}
		r, e := rootDir()
		if e != nil {
			return e
		}
		return dmg(r)
	case "disable-auto":
		if len(args) != 1 {
			return errors.New("disable-auto takes no arguments")
		}
		return disableAuto()
	case "brew-package":
		if len(args) != 1 {
			return errors.New("brew-package takes no arguments")
		}
		r, e := rootDir()
		if e != nil {
			return e
		}
		return brewPackage(r)
	case "install-auto":
		if len(args) != 1 {
			return errors.New("install-auto takes no arguments")
		}
		return installAuto()
	case "diagnose":
		return diagnoseCommand(args[1:])
	}
	return errors.New("unknown command: " + args[0])
}
func requireID(path string) error {
	m, e := readPlist(join(path, "Contents/Info.plist"))
	if e != nil {
		return e
	}
	if m["CFBundleIdentifier"] != identifier {
		return errors.New("unexpected app identifier: " + path)
	}
	return nil
}
func verify(path string) error {
	return run("/usr/bin/codesign", "--verify", "--deep", "--strict", path)
}
func helperPath(app string) string {
	return join(app, "Contents/Library/LoginItems/KCLAutoApply.app/Contents/MacOS/KCLAutoApply")
}
func agentPath() string { return join(home, "Library/LaunchAgents", agentLabel+".plist") }
func domain() string    { return "gui/" + strconv.Itoa(os.Getuid()) }
func register(app string) error {
	if e := run(lsregister, "-f", app); e != nil {
		return e
	}
	return run("/usr/bin/pluginkit", "-a", join(app, "Contents/PlugIns/KeychainCompatibilityLayer.appex"))
}
