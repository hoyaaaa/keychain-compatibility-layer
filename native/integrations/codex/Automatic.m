#import <AppKit/AppKit.h>
#include <signal.h>
#include <limits.h>

@interface KCLAutomatic : NSObject
@property NSString *targetPath;
@property NSString *bundleID;
@property NSString *library;
@property NSString *statusPath;
@property BOOL busy;
@property BOOL fixture;
- (void)record:(NSString *)state phase:(NSString *)phase pid:(pid_t)pid;
- (void)launched:(NSNotification *)notification;
@end

@implementation KCLAutomatic
- (void)record:(NSString *)state phase:(NSString *)phase pid:(pid_t)pid {
    NSDictionary *value = @{ @"state":state, @"phase":phase, @"target_pid":@(pid),
        @"watcher_pid":@(getpid()), @"target":self.targetPath,
        @"updated_at":[[NSISO8601DateFormatter new] stringFromDate:NSDate.date] };
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:self.statusPath options:NSDataWritingAtomic error:nil];
    fprintf(stdout,"%s: %s (pid=%d)\n",state.UTF8String,phase.UTF8String,pid); fflush(stdout);
}
- (BOOL)loaded:(NSRunningApplication *)app {
    NSString *directory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Keychain Compatibility Layer/runtime"];
    NSString *path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.loaded",app.processIdentifier]];
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    NSDate *date = attributes[NSFileModificationDate];
    return date && app.launchDate && [date timeIntervalSinceDate:app.launchDate] >= -5 &&
        [[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] isEqual:@"loaded\n"];
}
- (void)confirm:(NSRunningApplication *)app attempt:(NSUInteger)attempt {
    if ([self loaded:app]) {
        [self record:@"completed" phase:@"runtime compatibility loaded" pid:app.processIdentifier]; self.busy = NO; return;
    }
    if (app.terminated || attempt >= 50) {
        [self record:@"failed" phase:@"runtime library did not report loading; no retry loop" pid:app.processIdentifier]; self.busy = NO; return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ [self confirm:app attempt:attempt+1]; });
}
- (void)restartAfter:(NSRunningApplication *)old attempt:(NSUInteger)attempt {
    if (!old.terminated) {
        if (attempt >= 150) { [self record:@"failed" phase:@"graceful quit timed out; app was not forced closed" pid:old.processIdentifier]; self.busy = NO; return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ [self restartAfter:old attempt:attempt+1]; }); return;
    }
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.activates = YES;
    configuration.environment = @{@"DYLD_INSERT_LIBRARIES":self.library};
    [NSWorkspace.sharedWorkspace openApplicationAtURL:[NSURL fileURLWithPath:self.targetPath]
        configuration:configuration completionHandler:^(NSRunningApplication *app,NSError *error) {
        dispatch_async(dispatch_get_main_queue(),^{
            if (!app || error) { [self record:@"failed" phase:@"could not relaunch application" pid:0]; self.busy = NO; return; }
            [self confirm:app attempt:0];
        });
    }];
}
- (void)launched:(NSNotification *)notification {
    NSRunningApplication *app = notification.userInfo[NSWorkspaceApplicationKey];
    if (self.fixture) fprintf(stdout,"fixture launch event: expected bundle=%d path=%d\n",[app.bundleIdentifier isEqual:self.bundleID],[app.bundleURL.path isEqual:self.targetPath]);
    if (!app || ![app.bundleIdentifier isEqual:self.bundleID] ||
        ![app.bundleURL.path isEqual:self.targetPath] || self.busy) return;
    if ([self loaded:app]) { [self record:@"completed" phase:@"already compatible; no restart" pid:app.processIdentifier]; return; }
    self.busy = YES;
    [self record:@"running" phase:@"new vanilla launch detected; restarting once" pid:app.processIdentifier];
    if (![app terminate]) { [self record:@"failed" phase:@"graceful quit refused; app was not forced closed" pid:app.processIdentifier]; self.busy = NO; return; }
    [self restartAfter:app attempt:0];
}
@end

int main(int argc,const char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        __attribute__((objc_precise_lifetime)) KCLAutomatic *watcher = [KCLAutomatic new];
        watcher.targetPath = @"/Applications/ChatGPT.app"; watcher.bundleID = @"com.openai.codex";
        watcher.library = [NSHomeDirectory() stringByAppendingPathComponent:@"Applications/Keychain Compatibility Layer.app/Contents/Frameworks/KeychainCompatibilityLayerShim.dylib"];
        NSString *directory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Keychain Compatibility Layer/runtime"];
        [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
        watcher.statusPath = [directory stringByAppendingPathComponent:@"auto-apply-status.json"];
        pid_t parent = 0;
        if (argc >= 3 && strcmp(argv[argc-2],"--parent-pid")==0) {
            char *end = NULL; long value = strtol(argv[argc-1],&end,10);
            if (!end || *end || value <= 1 || value > INT_MAX || getppid() != (pid_t)value) return 2;
            parent = (pid_t)value; argc -= 2;
        }
        if (argc == 5 && strcmp(argv[1],"--fixture")==0 && strcmp(argv[3],"--library")==0) {
            watcher.fixture = YES; watcher.targetPath = @(argv[2]); watcher.library = @(argv[4]);
            watcher.bundleID = @"io.hoya.KCLAutoApplyFixture";
            watcher.statusPath = [directory stringByAppendingPathComponent:@"fixture-auto-apply-status.json"];
            if (![[NSBundle bundleWithPath:watcher.targetPath].bundleIdentifier isEqual:watcher.bundleID]) return 2;
        } else if (argc != 1) return 2;
        [watcher record:@"started" phase:@"registering launch observer" pid:0];
        [NSWorkspace.sharedWorkspace.notificationCenter addObserver:watcher selector:@selector(launched:) name:NSWorkspaceDidLaunchApplicationNotification object:nil];
        // Existing processes are deliberately left alone, including the active chat.
        [watcher record:@"running" phase:@"watching future launches; existing processes retained" pid:0];
        signal(SIGTERM,SIG_IGN);
        __attribute__((objc_precise_lifetime)) dispatch_source_t stopSignal = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,SIGTERM,0,dispatch_get_main_queue());
        dispatch_source_set_event_handler(stopSignal, ^{
            [watcher record:@"completed" phase:@"automatic application stopped" pid:0];
            [NSApp terminate:nil];
        });
        dispatch_resume(stopSignal);
        __attribute__((objc_precise_lifetime)) dispatch_source_t parentTimer = nil;
        if (parent) {
            parentTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
            dispatch_source_set_timer(parentTimer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),NSEC_PER_SEC,100*NSEC_PER_MSEC);
            dispatch_source_set_event_handler(parentTimer, ^{
                if (getppid() != parent) {
                    [watcher record:@"completed" phase:@"owner app exited; automatic application stopped" pid:0];
                    [NSApp terminate:nil];
                }
            });
            dispatch_resume(parentTimer);
        }
        [NSApp run];
    }
    return 0;
}
