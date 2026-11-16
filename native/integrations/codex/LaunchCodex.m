#import <AppKit/AppKit.h>
#import "CodexIntegration.h"

int LaunchCodex(BOOL interactive) {
    NSString *message = nil;
    if ([NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.openai.codex"].count)
        message = @"Codex가 이미 실행 중입니다. Codex를 ⌘Q로 종료한 뒤 Keychain Compatibility Layer에서 다시 실행해 주세요. 원본 파일은 변경하지 않습니다.";
    NSString *target = @"/Applications/ChatGPT.app/Contents/MacOS/ChatGPT";
    NSString *library = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"KeychainCompatibilityLayerShim.dylib"];
    if (!message && (![NSFileManager.defaultManager isExecutableFileAtPath:target] ||
        ![NSFileManager.defaultManager fileExistsAtPath:library])) message = @"Codex 원본 또는 호환 라이브러리를 찾지 못했습니다.";
    if (message) {
        if (interactive) {
            NSAlert *alert = [NSAlert new]; alert.messageText = @"Keychain Compatibility Layer";
            alert.informativeText = message; [alert runModal];
        } else fprintf(stderr,"%s\n",message.UTF8String);
        return 2;
    }
    NSTask *task = [NSTask new]; task.executableURL = [NSURL fileURLWithPath:target];
    NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
    environment[@"DYLD_INSERT_LIBRARIES"] = library; [environment removeObjectForKey:@"KCL_SHIM_TEST"];
    task.environment = environment;
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) { fprintf(stderr,"%s\n",error.localizedDescription.UTF8String); return 1; }
    printf("Launched original Codex with runtime software-key compatibility; pid=%d\n",task.processIdentifier);
    return 0;
}
