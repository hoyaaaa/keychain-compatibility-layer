#import <CryptoTokenKit/CryptoTokenKit.h>
#import <CommonCrypto/CommonDigest.h>
#import "KeyStore.h"
#import "TokenStore.h"

int Enroll(TKTokenDriverConfiguration *driver, NSString *instance, NSData *externalTag) {
    TKTokenConfiguration *config = driver.tokenConfigurations[instance];
    if (!config) config = [driver addTokenConfigurationForTokenInstanceID:instance];
    TKTokenWatcher *watcher = [TKTokenWatcher new];
    (void)watcher.tokenIDs;
    NSData *publicData = nil;
    OSStatus status = errSecItemNotFound;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:15];
    do {
        publicData = KCLCopyData(NO, instance, &status);
        if (publicData || status != errSecItemNotFound) break;
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    } while (deadline.timeIntervalSinceNow > 0);
    if (!publicData) { fprintf(stderr, "Extension public key not ready: %d\n", status); return 1; }
    TKTokenKeychainKey *item = [[TKTokenKeychainKey alloc] initWithCertificate:NULL objectID:instance];
    item.label = [NSString stringWithFormat:@"Keychain Compatibility Layer — %@ (software key)", instance];
    item.keyType = (__bridge NSString *)KCLBackingType(instance);
    item.keySizeInBits = KCLBackingSize(instance).integerValue; item.publicKeyData = publicData;
    unsigned char hash[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(publicData.bytes, (CC_LONG)publicData.length, hash);
    item.publicKeyHash = [NSData dataWithBytes:hash length:sizeof(hash)];
    item.applicationTag = externalTag ?: [@"io.hoya.KeychainCompatibilityLayer.published-key" dataUsingEncoding:NSUTF8StringEncoding]; item.canSign = YES;
    item.canDecrypt = NO; item.canPerformKeyExchange = NO; item.suitableForLogin = NO;
    // The provider itself requires native owner authentication for each signature.
    item.constraints = @{@(TKTokenOperationSignData):@YES};
    TKTokenConfiguration *store = driver.tokenConfigurations[KCLStoreInstance];
    if (!store) store = [driver addTokenConfigurationForTokenInstanceID:KCLStoreInstance];
    NSMutableArray *items = [NSMutableArray array];
    for (TKTokenKeychainItem *existing in store.keychainItems)
        if (![existing.objectID isEqual:instance]) [items addObject:existing];
    [items addObject:item]; store.keychainItems = items;
    [driver removeTokenConfigurationForTokenInstanceID:instance];
    return 0;
}
