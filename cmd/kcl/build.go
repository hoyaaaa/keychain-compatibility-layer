package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func build(root string) error {
	app := join(root, "build", appName)
	ext := join(app, "Contents/PlugIns/KeychainCompatibilityLayer.appex")
	auto := join(app, "Contents/Library/LoginItems/KCLAutoApply.app")
	// Rebuild only our generated bundle, so removed scripts cannot survive an update.
	if e := os.RemoveAll(app); e != nil {
		return e
	}
	for _, p := range []string{join(app, "Contents/MacOS"), join(app, "Contents/Frameworks"), join(app, "Contents/Resources"), join(ext, "Contents/MacOS"), join(auto, "Contents/MacOS")} {
		if e := os.MkdirAll(p, 0755); e != nil {
			return e
		}
	}
	icon, e := os.ReadFile(join(root, "assets/AppIcon.icns"))
	if e != nil {
		return e
	}
	license, e := os.ReadFile(join(root, "LICENSE"))
	if e != nil {
		return e
	}
	if e := atomicWrite(join(app, "Contents/Resources/LICENSE"), license, 0644); e != nil {
		return e
	}
	for _, b := range []struct{ path, id, exe, kind string }{{app, identifier, "KeychainCompatibilityLayer", "APPL"}, {ext, identifier + ".Driver", "KeychainCompatibilityLayerDriver", "XPC!"}, {auto, agentLabel, "KCLAutoApply", "APPL"}} {
		info := map[string]any{"CFBundleIdentifier": b.id, "CFBundleExecutable": b.exe, "CFBundlePackageType": b.kind, "CFBundleName": "Keychain Compatibility Layer", "CFBundleVersion": strings.TrimSpace(version), "CFBundleShortVersionString": strings.TrimSpace(version), "LSMinimumSystemVersion": "13.0"}
		info["CFBundleIconFile"] = "AppIcon"
		if e := atomicWrite(join(b.path, "Contents/Resources/AppIcon.icns"), icon, 0644); e != nil {
			return e
		}
		if b.path == ext {
			info["NSExtension"] = map[string]any{"NSExtensionPointIdentifier": "com.apple.ctk-tokens", "NSExtensionAttributes": map[string]any{"com.apple.ctk.class-id": b.id, "com.apple.ctk.driver-class": "KeychainCompatibilityLayerDriver"}}
		} else {
			info["LSUIElement"] = true
		}
		if e := writePlist(join(b.path, "Contents/Info.plist"), info); e != nil {
			return e
		}
	}
	base := []string{"xcrun", "clang", "-fobjc-arc", "-mmacosx-version-min=13.0", "-Wno-deprecated-declarations"}
	for _, directory := range []string{"native/core", "native/migration", "native/integrations/codex", "native/integrations/secretive"} {
		base = append(base, "-I", join(root, directory))
	}
	common := append(append([]string{}, base...), "-framework", "Foundation", "-framework", "CryptoTokenKit", "-framework", "Security", "-framework", "LocalAuthentication")
	compile := func(args ...string) error { return run(append(append([]string{}, common...), args...)...) }
	// Native packages have explicit source lists and one public header each.
	archive := func(name string, sources ...string) (string, error) {
		directory := join(root, "build/obj", name)
		if e := os.MkdirAll(directory, 0755); e != nil {
			return "", e
		}
		objects := []string{}
		for _, source := range sources {
			object := join(directory, strings.TrimSuffix(filepath.Base(source), ".m")+".o")
			args := append(append([]string{}, base...), "-c", join(root, source), "-o", object)
			if e := run(args...); e != nil {
				return "", e
			}
			objects = append(objects, object)
		}
		library := join(root, "build", "lib"+name+".a")
		if e := os.Remove(library); e != nil && !os.IsNotExist(e) {
			return "", e
		}
		if e := run(append([]string{"xcrun", "ar", "rcs", library}, objects...)...); e != nil {
			return "", e
		}
		return library, nil
	}
	core, e := archive("KCLCore", "native/core/Enroll.m", "native/core/Audit.m", "native/core/Purge.m")
	if e != nil {
		return e
	}
	codex, e := archive("KCLCodex", "native/integrations/codex/LaunchCodex.m")
	if e != nil {
		return e
	}
	secretive, e := archive("KCLSecretive", "native/integrations/secretive/SSHKeys.m", "native/integrations/secretive/SecretiveUI.m")
	if e != nil {
		return e
	}
	sign := func(path string, args ...string) error {
		return run(append([]string{"/usr/bin/codesign", "--force", "--sign", "-"}, append(args, path)...)...)
	}
	lib := join(app, "Contents/Frameworks/KeychainCompatibilityLayerShim.dylib")
	if e := compile("-dynamiclib", join(root, "native/integrations/codex/Compatibility.m"), "-o", lib); e != nil {
		return e
	}
	if e := sign(lib); e != nil {
		return e
	}
	if e := compile("-framework", "AppKit", join(root, "native/integrations/codex/Automatic.m"), "-o", helperPath(app)); e != nil {
		return e
	}
	if e := sign(auto); e != nil {
		return e
	}
	if e := compile("-framework", "AppKit", join(root, "native/app/Host.m"), join(root, "native/app/Application.m"), join(root, "native/migration/LegacyMigration.m"), codex, secretive, core, "-o", join(app, "Contents/MacOS/KeychainCompatibilityLayer")); e != nil {
		return e
	}
	if e := compile("-fapplication-extension", "-Wl,-e,_NSExtensionMain", join(root, "native/core/Driver.m"), "-o", join(ext, "Contents/MacOS/KeychainCompatibilityLayerDriver")); e != nil {
		return e
	}
	// Build for the same architecture as the native modules. No cgo or external packages.
	cli := join(app, "Contents/Resources/kcl")
	if e := run("go", "build", "-trimpath", "-ldflags", "-X main.version="+strings.TrimSpace(version), "-o", cli, "./cmd/kcl"); e != nil {
		return e
	}
	if e := sign(cli); e != nil {
		return e
	}
	for _, ent := range []struct {
		file, path, id string
		groups         []string
		sandbox        bool
	}{
		{"extension-entitlements.plist", ext, identifier + ".Driver", []string{identifier + ".Private", identifier + ".Public", legacyIdentifier + ".Private", legacyIdentifier + ".Public"}, true},
		{"host-entitlements.plist", app, identifier, []string{identifier + ".Public"}, false},
	} {
		m := map[string]any{"com.apple.application-identifier": ent.id, "keychain-access-groups": ent.groups}
		if ent.sandbox {
			m["com.apple.security.app-sandbox"] = true
		}
		p := join(root, "build", ent.file)
		if e := writePlist(p, m); e != nil {
			return e
		}
		if e := sign(ent.path, "--entitlements", p); e != nil {
			return e
		}
	}
	if e := verify(app); e != nil {
		return e
	}
	check := filepath.Join(root, "build/check")
	if e := compile(join(root, "compatibility/Check.m"), "-o", check); e != nil {
		return e
	}
	if e := sign(check); e != nil {
		return e
	}
	fmt.Println(app)
	return nil
}
