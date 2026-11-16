#import <AppKit/AppKit.h>
#import "SecretiveIntegration.h"

void KCLShowSecretiveKeyCreation(void) {
    NSAlert *prompt = [NSAlert new]; prompt.messageText = @"Create SSH key for Secretive / SSH 키 만들기";
    prompt.informativeText = @"Create a separate software RSA-2048 SSH key (RSA-SHA2-512 signatures). Secretive reads it through its smart-card store. Codex keys are not reused.\n별도 SSH 키를 만들며 Codex 키를 재사용하지 않습니다.";
    NSTextField *name = [[NSTextField alloc] initWithFrame:NSMakeRect(0,0,320,24)]; name.stringValue = @"Secretive SSH key"; prompt.accessoryView = name;
    [prompt addButtonWithTitle:@"Create / 만들기"]; [prompt addButtonWithTitle:@"Cancel / 취소"];
    if ([prompt runModal] != NSAlertFirstButtonReturn) return;
    NSTask *task = [NSTask new]; task.executableURL = NSBundle.mainBundle.executableURL;
    task.arguments = @[@"ssh-create",name.stringValue];
    NSPipe *pipe = [NSPipe pipe];task.standardOutput = pipe;task.standardError = pipe;
    NSError *error = nil;NSData *data = nil;
    if ([task launchAndReturnError:&error]) { data = [pipe.fileHandleForReading readDataToEndOfFile];[task waitUntilExit]; }
    NSDictionary *info = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSAlert *result = [NSAlert new];result.messageText = @"Keychain Compatibility Layer";
    if (!error && task.terminationStatus == 0 && [info[@"public_key"] isKindOfClass:NSString.class]) {
        result.informativeText = [NSString stringWithFormat:@"SSH key created. Open or restart Secretive to refresh its smart-card keys.\nSSH 키를 만들었습니다. Secretive를 새로 열면 표시됩니다.\n\n%@\n\n%@",info[@"fingerprint"],info[@"public_key"]];
        [result addButtonWithTitle:@"Copy public key / 공개키 복사"];[result addButtonWithTitle:@"Close / 닫기"];
        if ([result runModal] == NSAlertFirstButtonReturn) { [NSPasteboard.generalPasteboard clearContents];[NSPasteboard.generalPasteboard setString:info[@"public_key"] forType:NSPasteboardTypeString]; }
    } else {
        result.informativeText = error.localizedDescription ?: [[NSString alloc] initWithData:data ?: NSData.data encoding:NSUTF8StringEncoding] ?: @"Key creation failed.";[result runModal];
    }
}
