#import <CryptoTokenKit/CryptoTokenKit.h>
static NSString * const KCLStoreInstance = @"key-store";
static TKTokenKeychainKey *KCLPublishedKey(TKTokenDriverConfiguration *driver, NSString *instance) {
    for (TKTokenKeychainItem *item in driver.tokenConfigurations[KCLStoreInstance].keychainItems)
        if ([item isKindOfClass:TKTokenKeychainKey.class] && [item.objectID isEqual:instance]) return (TKTokenKeychainKey *)item;
    return nil;
}
