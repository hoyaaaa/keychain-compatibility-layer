#import <AppKit/AppKit.h>
#import "SecretiveIntegration.h"

static int Manage(NSString *action, NSArray<NSString *> *extra) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"kcl"]];
    task.arguments = [@[action] arrayByAddingObjectsFromArray:extra];
    NSPipe *output = [NSPipe pipe]; task.standardOutput = output; task.standardError = output;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        NSAlert *alert = [NSAlert new]; alert.messageText = @"Keychain Compatibility Layer";
        alert.informativeText = error.localizedDescription; [alert runModal]; return 1;
    }
    NSData *data = [output.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    if (task.terminationStatus != 0) {
        NSAlert *alert = [NSAlert new]; alert.messageText = @"Setup failed / 설정 실패";
        alert.informativeText = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"Please retry.";
        [alert runModal];
    }
    return task.terminationStatus;
}

@interface KCLAppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic,strong) NSTask *watcher;
@property(nonatomic,strong) NSStatusItem *statusItem;
@end
@implementation KCLAppDelegate
- (void)createSecretiveKey:(id)sender { KCLShowSecretiveKeyCreation(); }
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    if (self.watcher.running) { [self.watcher terminate]; [self.watcher waitUntilExit]; }
    return NSTerminateNow;
}
@end

int ShowPanel(void) {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [NSApp activateIgnoringOtherApps:YES];
    NSString *installed = [NSHomeDirectory() stringByAppendingPathComponent:@"Applications/Keychain Compatibility Layer.app"];
    NSString *current = NSBundle.mainBundle.bundlePath.stringByResolvingSymlinksInPath;
    if (![current isEqual:installed.stringByResolvingSymlinksInPath]) {
        NSAlert *setup = [NSAlert new]; setup.messageText = @"Install Keychain Compatibility Layer";
        setup.informativeText = @"Install for this user without developer tools. Codex and stored keys are preserved.\n현재 사용자에게 설치합니다. Codex 원본과 기존 키는 유지합니다.";
        [setup addButtonWithTitle:@"Install / 설치"]; [setup addButtonWithTitle:@"Cancel / 취소"];
        if ([setup runModal] != NSAlertFirstButtonReturn) return 0;
        int result = Manage(@"install", @[@"--source",current]);
        if (result != 0) return result;
        NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
        configuration.createsNewApplicationInstance = YES;
        [NSWorkspace.sharedWorkspace openApplicationAtURL:[NSURL fileURLWithPath:installed] configuration:configuration completionHandler:^(NSRunningApplication *app, NSError *error) {
            if (error) { NSAlert *alert = [NSAlert new]; alert.messageText = @"Open installed app"; alert.informativeText = error.localizedDescription; [alert runModal]; }
            [NSApp stop:nil];
        }];
        [NSApp run]; return 0;
    }
    // Migrate the old independent login helper: the app now owns its watcher.
    int result = Manage(@"disable-auto", @[]);
    if (result != 0) return result;
    __attribute__((objc_precise_lifetime)) KCLAppDelegate *delegate = [KCLAppDelegate new];
    NSApp.delegate = delegate;
    delegate.watcher = [NSTask new];
    delegate.watcher.executableURL = [NSURL fileURLWithPath:[installed stringByAppendingPathComponent:@"Contents/Library/LoginItems/KCLAutoApply.app/Contents/MacOS/KCLAutoApply"]];
    delegate.watcher.arguments = @[@"--parent-pid",[NSString stringWithFormat:@"%d",getpid()]];
    NSString *logs = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/Keychain Compatibility Layer"];
    [NSFileManager.defaultManager createDirectoryAtPath:logs withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    NSString *logPath = [logs stringByAppendingPathComponent:@"auto-apply.log"];
    if (![NSFileManager.defaultManager fileExistsAtPath:logPath]) [NSFileManager.defaultManager createFileAtPath:logPath contents:nil attributes:@{NSFilePosixPermissions:@0600}];
    NSFileHandle *log = [NSFileHandle fileHandleForWritingAtPath:logPath]; [log seekToEndOfFile];
    if (!log) return 1;
    delegate.watcher.standardOutput = log; delegate.watcher.standardError = log;
    NSError *error = nil;
    if (![delegate.watcher launchAndReturnError:&error]) {
        NSAlert *alert = [NSAlert new]; alert.messageText = @"Keychain Compatibility Layer"; alert.informativeText = error.localizedDescription; [alert runModal]; return 1;
    }
    delegate.watcher.terminationHandler = ^(NSTask *task) {
        dispatch_async(dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
    };
    delegate.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    delegate.statusItem.button.title = @"KCL";
    NSMenu *menu = [NSMenu new];
    NSMenuItem *status = [[NSMenuItem alloc] initWithTitle:@"Automatic application running / 자동 적용 중" action:nil keyEquivalent:@""]; status.enabled = NO; [menu addItem:status];
    NSMenuItem *create = [[NSMenuItem alloc] initWithTitle:@"Create SSH key for Secretive… / SSH 키 만들기…" action:@selector(createSecretiveKey:) keyEquivalent:@""];create.target=delegate;[menu addItem:create];
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit / 종료" action:@selector(terminate:) keyEquivalent:@"q"]; quit.target = NSApp; [menu addItem:quit];
    delegate.statusItem.menu = menu;
    [NSApp run]; return 0;
}
