#import <CryptoTokenKit/CryptoTokenKit.h>
#import "KeyStore.h"
#import "TokenStore.h"

int Purge(TKTokenDriverConfiguration *driver, NSString *instance) {

    [driver removeTokenConfigurationForTokenInstanceID:instance];
    TKTokenConfiguration *request = [driver addTokenConfigurationForTokenInstanceID:instance];
    request.configurationData = [@"purge-key" dataUsingEncoding:NSUTF8StringEncoding];
    TKTokenWatcher *watcher = [TKTokenWatcher new]; (void)watcher.tokenIDs;
    OSStatus status = errSecSuccess;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:15];
    do {
        KCLCopyData(NO, instance, &status);
        if (status == errSecItemNotFound) break;
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    } while (deadline.timeIntervalSinceNow > 0);
    [driver removeTokenConfigurationForTokenInstanceID:instance];
    if (status != errSecItemNotFound) { fprintf(stderr, "Private-key purge could not be confirmed\n"); return 1; }
    TKTokenConfiguration *store = driver.tokenConfigurations[KCLStoreInstance];
    NSMutableArray *items = [NSMutableArray array];
    for (TKTokenKeychainItem *item in store.keychainItems)
        if (![item.objectID isEqual:instance]) [items addObject:item];
    if (store) store.keychainItems = items;
    puts("Token key and its private/public Keychain items removed.");
    return 0;
}
