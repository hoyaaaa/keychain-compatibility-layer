#import <CryptoTokenKit/CryptoTokenKit.h>
#import "LegacyMigration.h"
#import "TokenStore.h"
#import "Core.h"

static int ImportKey(TKTokenDriverConfiguration *driver, NSString *instance, TKTokenKeychainKey *previous) {
    if (!previous.publicKeyData.length) return 1;
    NSData *tag = previous.applicationTag;
    if ([tag isEqual:[[KCLLegacyIdentifier stringByAppendingString:@".published-key"] dataUsingEncoding:NSUTF8StringEncoding]]) tag = nil;
    if (Enroll(driver,instance,tag) != 0) return 1;
    if (![previous.publicKeyData isEqual:KCLPublishedKey(driver,instance).publicKeyData]) {
        fprintf(stderr,"Migration refused: public-key identity changed; encrypted recovery material retained.\n"); return 1;
    }
    return 0;
}
int MigrateLegacy(TKTokenDriverConfiguration *driver) {
    // Move published metadata into one token. Backing-key accounts never change.
    for (NSString *instance in driver.tokenConfigurations.allKeys) {
        if ([instance isEqual:KCLStoreInstance]) continue;
        NSArray *items = driver.tokenConfigurations[instance].keychainItems;
        if (items.count == 0) continue;
        if (items.count != 1 || ![items.firstObject isKindOfClass:TKTokenKeychainKey.class]) return 1;
        if (ImportKey(driver,instance,items.firstObject) != 0) return 1;
    }
    TKTokenDriverConfiguration *old = TKTokenDriverConfiguration.driverConfigurations[[KCLLegacyIdentifier stringByAppendingString:@".Driver"]];
    for (NSString *instance in old.tokenConfigurations.allKeys) {
        NSArray *items = old.tokenConfigurations[instance].keychainItems;
        if (items.count == 0) continue;
        if (items.count != 1 || ![items.firstObject isKindOfClass:TKTokenKeychainKey.class]) return 1;
        if (ImportKey(driver,instance,items.firstObject) != 0) return 1;
    }
    for (NSString *instance in old.tokenConfigurations.allKeys) [old removeTokenConfigurationForTokenInstanceID:instance];
    puts("Token-store migration complete; existing public-key identities verified."); return 0;
}
