#import <CryptoTokenKit/CryptoTokenKit.h>
#import "TokenStore.h"
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#import "Core.h"
#import "CodexIntegration.h"
#import "SecretiveIntegration.h"
#import "LegacyMigration.h"
extern int ShowPanel(void);

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc == 1) return ShowPanel();
        if (strcmp(argv[1],"launch-codex") == 0) return LaunchCodex(NO);
        if (strcmp(argv[1],"diagnose") == 0) {
            NSTask *task = [NSTask new];
            task.executableURL = [NSURL fileURLWithPath:[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"kcl"]];
            NSMutableArray *arguments = [NSMutableArray arrayWithObject:@"diagnose"];
            for (int i=2;i<argc;i++) [arguments addObject:@(argv[i])];
            task.arguments = arguments;
            NSError *error = nil;
            if (![task launchAndReturnError:&error]) { fprintf(stderr,"%s\n",error.localizedDescription.UTF8String); return 1; }
            [task waitUntilExit]; return task.terminationStatus;
        }
        NSString *requested = @(argv[1]);
        if ([@[@"enroll",@"ssh-create",@"purge",@"migrate-legacy",@"register",@"unregister"] containsObject:requested]) {
            NSString *directory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Keychain Compatibility Layer/runtime"];
            if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil]) return 1;
            int lock = open([[directory stringByAppendingPathComponent:@"control.lock"] fileSystemRepresentation],O_CREAT|O_RDWR|O_CLOEXEC|O_NOFOLLOW,0600);
            if (lock < 0 || flock(lock,LOCK_EX) != 0) { if(lock>=0)close(lock);fprintf(stderr,"Cannot lock token-store update.\n");return 1; }
            // Process lifetime owns the lock; CLI exit releases it on every return path.
        }
        NSDictionary *drivers = TKTokenDriverConfiguration.driverConfigurations;
        TKTokenDriverConfiguration *driver = drivers[@"io.hoya.KeychainCompatibilityLayer.Driver"];
        if (!driver) {
            fprintf(stderr, "Token extension not available to host (drivers=%lu)\n", drivers.count);
            return 1;
        }
        NSString *action = argc > 1 ? @(argv[1]) : @"status";
        if ([action isEqual:@"migrate-legacy"]) return MigrateLegacy(driver);
        if ([action isEqual:@"ssh-create"]) return CreateSSHKey(driver,argc > 2 ? @(argv[2]) : @"Secretive SSH key");
        if ([action isEqual:@"ssh-list"]) return ListSSHKeys(driver);
        if ([action isEqual:@"list"]) {
            NSData *data = [NSJSONSerialization dataWithJSONObject:[[driver.tokenConfigurations[KCLStoreInstance].keychainItems valueForKey:@"objectID"] sortedArrayUsingSelector:@selector(compare:)] ?: @[] options:0 error:nil];
            puts([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String); return 0;
        }
        NSString *instance = argc > 2 ? @(argv[2]) : @"local-software";
        NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789-"] invertedSet];
        if (instance.length == 0 || instance.length > 64 || [instance isEqual:KCLStoreInstance] || [instance rangeOfCharacterFromSet:invalid].location != NSNotFound) {
            fprintf(stderr, "Invalid token instance\n"); return 2;
        }
        if ([action isEqual:@"audit"]) return Audit(instance);
        if ([action isEqual:@"purge"]) return Purge(driver, instance);
        if ([action isEqual:@"enroll"]) {
            NSData *tag = argc > 3 ? [[NSData alloc] initWithBase64EncodedString:@(argv[3]) options:0] : nil;
            if (argc > 3 && (!tag || tag.length == 0 || tag.length > 1024)) return 2;
            return Enroll(driver, instance, tag);
        }
        if ([action isEqual:@"register"]) {
            if (!driver.tokenConfigurations[instance])
                [driver addTokenConfigurationForTokenInstanceID:instance];
        } else if ([action isEqual:@"unregister"]) {
            [driver removeTokenConfigurationForTokenInstanceID:instance];
        }
        TKTokenWatcher *watcher = [TKTokenWatcher new];
        NSUInteger ownTokens = 0;
        for (NSString *token in watcher.tokenIDs)
            if ([token hasPrefix:@"io.hoya.KeychainCompatibilityLayer.Driver"]) ownTokens++;
        printf("driver: available; configurations: %lu; own visible tokens: %lu; published keys: %lu\n",
               driver.tokenConfigurations.count, ownTokens,
               driver.tokenConfigurations[KCLStoreInstance].keychainItems.count);
        return 0;
    }
}
