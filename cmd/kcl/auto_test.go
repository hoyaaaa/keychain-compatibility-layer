package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestAutomaticFixture(t *testing.T) {
	if os.Getenv("KCL_TEST_AUTO") != "1" {
		t.Skip("opt-in GUI fixture: make test-auto")
	}
	root, e := filepath.Abs("../..")
	if e != nil {
		t.Fatal(e)
	}
	fixture := join(root, "build/AutoApplyFixture.app")
	if e := os.RemoveAll(fixture); e != nil {
		t.Fatal(e)
	}
	exe := join(fixture, "Contents/MacOS/KCLFixture")
	os.MkdirAll(filepath.Dir(exe), 0755)
	must := func(args ...string) {
		t.Helper()
		if e := run(args...); e != nil {
			t.Fatal(e)
		}
	}
	if e := writePlist(join(fixture, "Contents/Info.plist"), map[string]any{"CFBundleIdentifier": "io.hoya.KCLAutoApplyFixture", "CFBundleExecutable": "KCLFixture", "CFBundlePackageType": "APPL", "CFBundleName": "KCL Auto Apply Fixture", "CFBundleVersion": "1"}); e != nil {
		t.Fatal(e)
	}
	must("xcrun", "clang", "-fobjc-arc", "-include", "fcntl.h", "-framework", "AppKit", join(root, "compatibility/AutoFixture.m"), "-o", exe)
	must("codesign", "--force", "--sign", "-", fixture)
	must(lsregister, "-f", fixture)
	lib := join(root, "build/fixture-probe.dylib")
	must("xcrun", "clang", "-dynamiclib", join(root, "compatibility/AutoFixtureProbe.c"), "-o", lib)
	must("codesign", "--force", "--sign", "-", lib)
	dir := join(home, "Library/Application Support/Keychain Compatibility Layer/runtime")
	os.MkdirAll(dir, 0700)
	status, events := join(dir, "fixture-auto-apply-status.json"), join(dir, "fixture-launches.log")
	os.Remove(status)
	os.Remove(events)
	log, e := os.Create(join(root, "build/auto-fixture-watcher.log"))
	if e != nil {
		t.Fatal(e)
	}
	defer log.Close()
	watcher := exec.Command(helperPath(join(root, "build", appName)), "--fixture", fixture, "--library", lib)
	watcher.Stdout = log
	watcher.Stderr = log
	if e := watcher.Start(); e != nil {
		t.Fatal(e)
	}
	t.Cleanup(func() {
		watcher.Process.Signal(syscall.SIGTERM)
		watcher.Wait()
		b, _ := os.ReadFile(events)
		for _, line := range strings.Split(strings.TrimSpace(string(b)), "\n") {
			f := strings.Fields(line)
			if len(f) != 2 {
				continue
			}
			pid, e := strconv.Atoi(f[0])
			if e != nil {
				continue
			}
			actual, ok := capture("/bin/ps", "-p", f[0], "-o", "comm=")
			if ok && strings.TrimSpace(actual) == exe {
				syscall.Kill(pid, syscall.SIGTERM)
			}
		}
	})
	deadline := time.Now().Add(5 * time.Second)
	for !exists(status) && time.Now().Before(deadline) {
		time.Sleep(100 * time.Millisecond)
	}
	if !exists(status) {
		t.Fatal("watcher did not start")
	}
	must("open", "-a", fixture)
	deadline = time.Now().Add(25 * time.Second)
	var outcome map[string]any
	for time.Now().Before(deadline) {
		b, _ := os.ReadFile(status)
		json.Unmarshal(b, &outcome)
		if outcome["state"] == "completed" || outcome["state"] == "failed" {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}
	if outcome["state"] != "completed" || outcome["phase"] != "runtime compatibility loaded" {
		t.Fatal("automatic application failed", outcome)
	}
	time.Sleep(time.Second)
	b, e := os.ReadFile(events)
	if e != nil {
		t.Fatal(e)
	}
	lines := strings.Split(strings.TrimSpace(string(b)), "\n")
	if len(lines) != 2 || !strings.HasSuffix(lines[0], " vanilla") || !strings.HasSuffix(lines[1], " loaded") {
		t.Fatal("expected exactly one restart", lines)
	}
}

func TestWatcherStopsWithOwner(t *testing.T) {
	if os.Getenv("KCL_TEST_AUTO") != "1" {
		t.Skip("opt-in GUI lifecycle check")
	}
	root, e := filepath.Abs("../..")
	if e != nil {
		t.Fatal(e)
	}
	fixture := join(root, "build/AutoApplyFixture.app")
	lib := join(root, "build/fixture-probe.dylib")
	if !exists(fixture) || !exists(lib) {
		t.Fatal("run the fixture build first with make test-auto")
	}
	pidFile := join(t.TempDir(), "child.pid")
	log, e := os.CreateTemp(t.TempDir(), "watcher-log")
	if e != nil {
		t.Fatal(e)
	}
	defer log.Close()
	owner := exec.Command("/bin/sh", "-c", `"$1" --fixture "$2" --library "$3" --parent-pid $$ & echo $! > "$4"; wait`, "owner", helperPath(join(root, "build", appName)), fixture, lib, pidFile)
	owner.Stdout = log
	owner.Stderr = log
	if e := owner.Start(); e != nil {
		t.Fatal(e)
	}
	t.Cleanup(func() { owner.Process.Kill(); owner.Wait() })
	var pid int
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		b, _ := os.ReadFile(pidFile)
		pid, _ = strconv.Atoi(strings.TrimSpace(string(b)))
		if pid > 0 {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}
	if pid <= 0 {
		t.Fatal("child did not start")
	}
	t.Cleanup(func() { syscall.Kill(pid, syscall.SIGTERM) })
	status := join(home, "Library/Application Support/Keychain Compatibility Layer/runtime/fixture-auto-apply-status.json")
	for time.Now().Before(deadline) {
		b, _ := os.ReadFile(status)
		var v map[string]any
		json.Unmarshal(b, &v)
		if v["watcher_pid"] == float64(pid) && v["state"] == "running" {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}
	owner.Process.Kill()
	owner.Wait()
	deadline = time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		b, _ := os.ReadFile(status)
		var v map[string]any
		json.Unmarshal(b, &v)
		if v["watcher_pid"] == float64(pid) && v["phase"] == "owner app exited; automatic application stopped" {
			return
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatal("watcher did not stop after owner was force-closed")
}
