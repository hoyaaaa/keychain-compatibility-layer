package main

import (
	"fmt"
	"os"
	"strings"
	"time"
)

// Old identifiers are kept only at the upgrade boundary, never as new identities.
const legacyIdentifier = "io.hoya.FakeSecureEnclave"
const legacyAppName = "Fake Secure Enclave.app"
const legacyStorageName = "Fake Secure Enclave"

func requirePreviousID(path string) error {
	m, e := readPlist(join(path, "Contents/Info.plist"))
	if e != nil {
		return e
	}
	if m["CFBundleIdentifier"] != identifier && m["CFBundleIdentifier"] != legacyIdentifier {
		return fmt.Errorf("unexpected existing app identifier")
	}
	return nil
}
func migrateLegacy(target string) error {
	if e := run(join(target, "Contents/MacOS/KeychainCompatibilityLayer"), "migrate-legacy"); e != nil {
		return e
	}
	if matches, found := capture("/usr/bin/pluginkit", "-m", "-i", legacyIdentifier+".Driver"); found && strings.TrimSpace(matches) != "" {
		if e := run("/usr/bin/pluginkit", "-e", "ignore", "-i", legacyIdentifier+".Driver"); e != nil {
			return e
		}
	}
	oldAgent := join(home, "Library/LaunchAgents", legacyIdentifier+".AutoApply.plist")
	if exists(oldAgent) {
		m, e := readPlist(oldAgent)
		if e != nil {
			return e
		}
		args, ok := m["ProgramArguments"].([]any)
		expected := join(home, "Applications", appName, "Contents/Library/LoginItems/FSEAutoApply.app/Contents/MacOS/FSEAutoApply")
		if m["Label"] != legacyIdentifier+".AutoApply" || !ok || len(args) != 1 || args[0] != expected {
			return fmt.Errorf("unexpected legacy agent; left untouched")
		}
		capture("/bin/launchctl", "bootout", domain(), oldAgent)
		if e := os.Remove(oldAgent); e != nil {
			return e
		}
	}
	for _, relative := range []string{"Library/Application Support", "Library/Logs"} {
		old := join(home, relative, legacyStorageName)
		if exists(old) {
			new := join(home, relative, "Keychain Compatibility Layer", "legacy-archive")
			if exists(new) {
				new = join(home, relative, fmt.Sprintf("legacy-archive-%d", time.Now().UnixNano()))
			}
			{
				if e := os.MkdirAll(join(home, relative, "Keychain Compatibility Layer"), 0700); e != nil {
					return e
				}
				if e := os.Rename(old, new); e != nil {
					return e
				}
			}
		}
	}
	alias := join(home, "Applications", legacyAppName)
	if st, e := os.Lstat(alias); e == nil && st.Mode()&os.ModeSymlink != 0 {
		p, e := os.Readlink(alias)
		if e != nil || p != target {
			return fmt.Errorf("unexpected legacy alias; retained")
		}
		return os.Remove(alias)
	}
	return nil
}
