package main

import (
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"testing"
)

func TestNativePackageBoundaries(t *testing.T) {
	root, e := filepath.Abs("../..")
	if e != nil {
		t.Fatal(e)
	}
	rules := []struct{ directory, forbidden string }{
		{"native/core", `Codex|Secretive|com\.openai|com\.maxgoedjen`},
		{"native/integrations/codex", `SecretiveIntegration\.h`},
		{"native/integrations/secretive", `CodexIntegration\.h`},
		{"native/app", `int LaunchCodex\(|static void SSHString\(|SecKeyCreateSignature\(`},
	}
	for _, rule := range rules {
		pattern := regexp.MustCompile(rule.forbidden)
		e := filepath.WalkDir(join(root, rule.directory), func(path string, entry fs.DirEntry, e error) error {
			if e != nil {
				return e
			}
			if entry.IsDir() {
				return nil
			}
			b, e := os.ReadFile(path)
			if e != nil {
				return e
			}
			if pattern.Match(b) {
				t.Errorf("package boundary crossed: %s", path)
			}
			return nil
		})
		if e != nil {
			t.Fatal(e)
		}
	}
}
