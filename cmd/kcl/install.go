package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"reflect"
	"time"
)

// Move on the target filesystem; retain the old bundle until activation succeeds.
func replaceBundle(staged, target, backup, previous string, activate func() error) (err error) {
	moved, installed := false, false
	defer func() {
		if err != nil {
			var recovery []error
			if installed {
				if e := os.Rename(target, staged); e != nil {
					recovery = append(recovery, e)
				}
			}
			if moved {
				if e := os.Rename(backup, previous); e != nil {
					recovery = append(recovery, e)
				}
			}
			err = errors.Join(append([]error{err}, recovery...)...)
		}
	}()
	if previous != "" {
		if err = os.Rename(previous, backup); err != nil {
			return
		}
		moved = true
	}
	if err = os.Rename(staged, target); err != nil {
		return
	}
	installed = true
	err = activate()
	return
}
func validAgent(m map[string]any, target, legacy string) bool {
	if m["Label"] != agentLabel {
		return false
	}
	args, ok := m["ProgramArguments"].([]any)
	return ok && (reflect.DeepEqual(args, []any{helperPath(target)}) || reflect.DeepEqual(args, []any{helperPath(legacy)}))
}
func install(source string, check bool) (err error) {
	target := join(home, "Applications", appName)
	legacy := join(home, "Applications", legacyAppName)
	agent := agentPath()
	if e := requireID(source); e != nil {
		return e
	}
	if e := verify(source); e != nil {
		return e
	}
	previous := ""
	if exists(target) {
		previous = target
	} else if st, e := os.Lstat(legacy); e == nil && st.Mode()&os.ModeSymlink == 0 {
		previous = legacy
	}
	if previous != "" {
		if e := requirePreviousID(previous); e != nil {
			return e
		}
	}
	if st, e := os.Lstat(legacy); e == nil && st.Mode()&os.ModeSymlink != 0 {
		p, e := os.Readlink(legacy)
		if e != nil || p != target {
			return errors.New("unexpected legacy compatibility alias")
		}
	}
	var config map[string]any
	agentBytes, e := os.ReadFile(agent)
	if e == nil {
		config, e = readPlist(agent)
		if e != nil {
			return e
		}
		if !validAgent(config, target, legacy) {
			return errors.New("unexpected auto-apply agent")
		}
	} else if !os.IsNotExist(e) {
		return e
	}
	_, loaded := capture("/bin/launchctl", "print", domain()+"/"+agentLabel)
	loaded = loaded && config != nil
	if check {
		fmt.Println("Source signature, target identity, compatibility alias and agent configuration: PASS; no changes made.")
		return nil
	}
	runtimeDir := join(home, "Library/Application Support/Keychain Compatibility Layer/runtime")
	lastState := ""
	record := func(state, phase string, cause error) error {
		v := map[string]any{"state": state, "phase": phase, "target": target}
		if cause != nil {
			v["error"] = cause.Error()
		}
		b, e := json.MarshalIndent(v, "", "  ")
		if e != nil {
			return e
		}
		e = atomicWrite(join(runtimeDir, "install-status.json"), append(b, '\n'), 0600)
		if e == nil {
			lastState = state
		}
		return e
	}
	if e := record("started", "preflight passed", nil); e != nil {
		return e
	}
	defer func() {
		if err != nil && lastState != "failed" {
			record("failed", "installation did not complete; inspect retained recovery files", err)
		}
	}()
	if loaded {
		b, e := os.ReadFile(join(runtimeDir, "auto-apply-status.json"))
		if e != nil && !os.IsNotExist(e) {
			return e
		}
		if e == nil {
			var s map[string]any
			if e = json.Unmarshal(b, &s); e != nil {
				return e
			}
			if s["phase"] == "new vanilla launch detected; restarting once" {
				err = errors.New("automatic restart in progress; retry after it finishes")
				record("failed", "live app retained", err)
				return err
			}
		}
	}
	if e := os.MkdirAll(join(home, "Applications"), 0755); e != nil {
		return e
	}
	staging, e := os.MkdirTemp(join(home, "Applications"), ".kcl-install-")
	if e != nil {
		return e
	}
	// Keep staged data on rollback failure for manual recovery rather than deleting it.
	success := false
	defer func() {
		if success {
			os.RemoveAll(staging)
		}
	}()
	staged := join(staging, appName)
	backup := join(staging, "previous.app")
	stopped, activated := false, false
	defer func() {
		if err == nil || activated {
			return
		}
		var recovery []error
		if stopped {
			capture("/bin/launchctl", "bootout", domain(), agent)
		}
		if agentBytes != nil {
			if e := atomicWrite(agent, agentBytes, 0644); e != nil {
				recovery = append(recovery, e)
			}
		}
		if stopped {
			if previous != "" && exists(previous) {
				if e := register(previous); e != nil {
					recovery = append(recovery, e)
				}
			}
			if e := run("/bin/launchctl", "bootstrap", domain(), agent); e != nil {
				recovery = append(recovery, e)
			}
		}
		err = errors.Join(append([]error{err}, recovery...)...)
		phase := "previous app and startup configuration preserved/restored"
		if len(recovery) > 0 {
			phase = "rollback incomplete; recovery files retained at " + staging
		}
		record("failed", phase, err)
	}()
	if err = run("/usr/bin/ditto", source, staged); err != nil {
		return
	}
	if err = verify(staged); err != nil {
		return
	}
	if err = record("running", "staged copy verified", nil); err != nil {
		return
	}
	if loaded {
		if err = run("/bin/launchctl", "bootout", domain(), agent); err != nil {
			return
		}
		stopped = true
	}
	err = replaceBundle(staged, target, backup, previous, func() error {
		if e := register(target); e != nil {
			return e
		}
		if e := migrateLegacy(target); e != nil {
			return e
		}
		if config != nil {
			config["ProgramArguments"] = []string{helperPath(target)}
			if e := writePlist(agent, config); e != nil {
				return e
			}
		}
		if loaded {
			return run("/bin/launchctl", "bootstrap", domain(), agent)
		}
		return nil
	})
	if err != nil {
		return
	}
	activated = true
	// Old extensions can still be mapped by an existing process; keep the old bundle.
	if previous != "" {
		retained := join(home, "Applications", fmt.Sprintf(".kcl-previous-install-%d.app", time.Now().UnixNano()))
		if err = os.Rename(backup, retained); err != nil {
			record("failed", "new installation active; old bundle retained at "+backup, err)
			return err
		}
	}
	success = true
	if err = record("completed", "installed and prior startup state preserved", nil); err != nil {
		return
	}
	fmt.Println("Installed", target, "; Codex untouched.")
	return nil
}
func installAuto() error {
	target := join(home, "Applications", appName)
	if e := requireID(target); e != nil {
		return e
	}
	if e := verify(target); e != nil {
		return e
	}
	if !exists(helperPath(target)) {
		return errors.New("build and install the app first")
	}
	logs := join(home, "Library/Logs/Keychain Compatibility Layer")
	if e := os.MkdirAll(logs, 0700); e != nil {
		return e
	}
	path := agentPath()
	if exists(path) {
		m, e := readPlist(path)
		if e != nil {
			return e
		}
		if !validAgent(m, target, target) {
			return errors.New("unexpected existing agent configuration")
		}
	}
	config := map[string]any{"Label": agentLabel, "ProgramArguments": []string{helperPath(target)}, "RunAtLoad": true, "KeepAlive": true, "ProcessType": "Background", "ThrottleInterval": 10, "LimitLoadToSessionType": "Aqua", "StandardOutPath": join(logs, "auto-apply.log"), "StandardErrorPath": join(logs, "auto-apply-error.log")}
	if e := writePlist(path, config); e != nil {
		return e
	}
	capture("/bin/launchctl", "bootout", domain(), path)
	if e := run("/bin/launchctl", "enable", domain()+"/"+agentLabel); e != nil {
		return e
	}
	if e := run("/bin/launchctl", "bootstrap", domain(), path); e != nil {
		return e
	}
	fmt.Println("Enabled", agentLabel, "; current Codex process retained.")
	return nil
}
