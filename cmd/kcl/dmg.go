package main

import (
	"crypto/sha256"
	"fmt"
	"os"
	"regexp"
	"runtime"
	"strings"
)

func dmg(root string) error {
	v := strings.TrimSpace(version)
	if !regexp.MustCompile(`^[0-9]+\.[0-9]+\.[0-9]+$`).MatchString(v) {
		return fmt.Errorf("invalid release version: %q", v)
	}
	if runtime.GOOS != "darwin" || runtime.GOARCH != "amd64" {
		return fmt.Errorf("the current runtime integration requires an Intel macOS build")
	}
	app := join(root, "build", appName)
	if e := requireID(app); e != nil {
		return e
	}
	if e := verify(app); e != nil {
		return e
	}
	info, e := readPlist(join(app, "Contents/Info.plist"))
	if e != nil {
		return e
	}
	if info["CFBundleShortVersionString"] != v {
		return fmt.Errorf("bundle version does not match VERSION")
	}
	stage, e := os.MkdirTemp(join(root, "build"), ".dmg-stage-")
	if e != nil {
		return e
	}
	defer os.RemoveAll(stage)
	if e := run("/usr/bin/ditto", app, join(stage, appName)); e != nil {
		return e
	}
	instructions := []byte("Keychain Compatibility Layer " + v + " (Intel macOS)\n\nOpen the app and choose Install for This User.\nThe installed app starts automatic application immediately. Keep it open; use KCL > Quit to stop.\nNo Homebrew, Go, Python or Xcode is needed to use the app.\n\nThis build is ad-hoc signed and NOT notarized. It is a test prerelease,\nnot a Gatekeeper-approved public release. Do not disable macOS security globally.\nThe original Codex application is never modified or copied.\n\n앱을 열고 ‘현재 사용자에게 설치’를 선택하세요. 설치된 앱은 바로 자동 적용됩니다. 종료하려면 메뉴 막대 KCL에서 종료하세요.\n打开应用并选择“为当前用户安装”，安装后应用会自动运行；退出 KCL 即停止。\nアプリを開いて「このユーザにインストール」を選び、アプリの起動中は自動適用されます。\n")
	if e := os.WriteFile(join(stage, "READ ME.txt"), instructions, 0644); e != nil {
		return e
	}
	license, e := os.ReadFile(join(root, "LICENSE"))
	if e != nil {
		return e
	}
	if e := atomicWrite(join(stage, "LICENSE"), license, 0644); e != nil {
		return e
	}
	output := join(root, "build", "Keychain-Compatibility-Layer-"+v+"-macOS-x86_64.dmg")
	if e := run("/usr/bin/hdiutil", "create", "-ov", "-format", "UDZO", "-fs", "HFS+", "-volname", "Keychain Compatibility Layer "+v, "-srcfolder", stage, output); e != nil {
		return e
	}
	if e := run("/usr/bin/hdiutil", "verify", output); e != nil {
		return e
	}
	b, e := os.ReadFile(output)
	if e != nil {
		return e
	}
	if e := atomicWrite(output+".sha256", []byte(fmt.Sprintf("%x  %s\n", sha256.Sum256(b), "Keychain-Compatibility-Layer-"+v+"-macOS-x86_64.dmg")), 0644); e != nil {
		return e
	}
	fmt.Println(output)
	return nil
}
func disableAuto() error {
	target := join(home, "Applications", appName)
	p := agentPath()
	if exists(p) {
		m, e := readPlist(p)
		if e != nil {
			return e
		}
		if !validAgent(m, target, target) {
			return fmt.Errorf("unexpected auto-apply agent")
		}
	}
	if e := run("/bin/launchctl", "disable", domain()+"/"+agentLabel); e != nil {
		return e
	}
	_, loaded := capture("/bin/launchctl", "print", domain()+"/"+agentLabel)
	if loaded {
		if e := run("/bin/launchctl", "bootout", domain(), p); e != nil {
			return e
		}
	}
	fmt.Println("Automatic application disabled; stored keys and Codex unchanged.")
	return nil
}
