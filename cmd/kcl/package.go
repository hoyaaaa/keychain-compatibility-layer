package main

import (
	"crypto/sha256"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

func brewPackage(root string) error {
	v := strings.TrimSpace(version)
	if !regexp.MustCompile(`^[0-9]+\.[0-9]+\.[0-9]+$`).MatchString(v) {
		return fmt.Errorf("invalid release version: %q", v)
	}
	archive := join(root, "build", "keychain-compatibility-layer-"+v+".tar.gz")
	if e := os.MkdirAll(filepath.Dir(archive), 0755); e != nil {
		return e
	}
	// Include an explicit source allowlist; no keys, logs, installed bundles or local state.
	args := []string{"/usr/bin/tar", "-czf", archive, "-C", root, "--exclude=.DS_Store", "VERSION", "LICENSE", "go.mod", "Makefile", "cmd", "docs", "README.md", "README.ko.md", "README.zh-CN.md", "README.ja.md", "CONTRIBUTING.md", "CHANGELOG.md", "REFERENCE_REVIEW.md", "scripts", "assets", "native"}
	args = append(args, "compatibility/Check.m", "compatibility/AutoFixture.m", "compatibility/AutoFixtureProbe.c", "compatibility/check-policy.m", "compatibility/check.cjs", "compatibility/probe.c", "compatibility/probe-target.c", "compatibility/check-ssh.m", "compatibility/check-ssh-token.m")
	if e := run(args...); e != nil {
		return e
	}
	b, e := os.ReadFile(archive)
	if e != nil {
		return e
	}
	formula := fmt.Sprintf(`class KeychainCompatibilityLayer < Formula
  desc "Software-backed Keychain compatibility for specific Codex device-key failures"
  url "file://%s"
  version "%s"
  sha256 "%x"

  depends_on :macos
  depends_on arch: :x86_64
  depends_on "go" => :build

  def install
    system "make", "all"
    prefix.install "build/Keychain Compatibility Layer.app"
    bin.install "build/kcl"
  end

  def caveats
    <<~EOS
      The app is kept in the Homebrew prefix. To install it for your user:
        kcl install --source "#{prefix}/Keychain Compatibility Layer.app"
        kcl install-auto
      Automatic application requires a GUI login session. Existing Codex processes are retained.
      Repeat kcl install --source after brew upgrade to update the per-user app safely.
    EOS
  end

  test do
    assert_equal version.to_s, shell_output("#{bin}/kcl version").strip
    system bin/"kcl", "diagnose", "--self-test"
  end
end
`, archive, v, sha256.Sum256(b))
	p := join(root, "build/Formula/keychain-compatibility-layer.rb")
	if e := atomicWrite(p, []byte(formula), 0644); e != nil {
		return e
	}
	fmt.Println(p)
	return nil
}
