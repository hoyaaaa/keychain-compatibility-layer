#import <Security/Security.h>
#import <Foundation/Foundation.h>
#import "LegacyMigration.h"

static NSString * const KCLPrivateGroup = @"io.hoya.KeychainCompatibilityLayer.Private";
static NSString * const KCLPublicGroup = @"io.hoya.KeychainCompatibilityLayer.Public";
static CFStringRef KCLBackingType(NSString *instance) {
    return [instance hasPrefix:@"ssh-rsa-"] ? kSecAttrKeyTypeRSA : kSecAttrKeyTypeECSECPrimeRandom;
}
static NSNumber *KCLBackingSize(NSString *instance) { return [instance hasPrefix:@"ssh-rsa-"] ? @2048 : @256; }
static NSString *KCLAccount(NSString *instance) {
    return [instance isEqual:@"local-software"] ? @"signing-key.v3" : [@"signing-key.v3." stringByAppendingString:instance];
}

static NSMutableDictionary *KCLQuery(BOOL privateKey, NSString *instance) {
    return [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:@"Keychain Compatibility Layer",
        (__bridge id)kSecAttrAccount:KCLAccount(instance),
        (__bridge id)kSecAttrAccessGroup:privateKey ? KCLPrivateGroup : KCLPublicGroup,
        (__bridge id)kSecUseDataProtectionKeychain:@YES} mutableCopy];
}
static OSStatus KCLStore(BOOL privateKey, NSString *instance, NSData *data) {
    NSMutableDictionary *query = KCLQuery(privateKey, instance);
    query[(__bridge id)kSecValueData] = data;
    query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
    query[(__bridge id)kSecAttrLabel] = privateKey ? @"Keychain Compatibility Layer private signing material" : @"Keychain Compatibility Layer public key";
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    if (status == errSecDuplicateItem && !privateKey) {
        status = SecItemUpdate((__bridge CFDictionaryRef)KCLQuery(NO, instance),
            (__bridge CFDictionaryRef)@{(__bridge id)kSecValueData:data});
    }
    return status;
}

static NSData *KCLCopyData(BOOL privateKey, NSString *instance, OSStatus *status) {
    NSMutableDictionary *query = KCLQuery(privateKey, instance);
    query[(__bridge id)kSecReturnData] = @YES;
    CFTypeRef result = NULL;
    *status = SecItemCopyMatching((__bridge CFDictionaryRef)query,&result);
    if (*status != errSecItemNotFound || !privateKey) return CFBridgingRelease(result);
    // Copy within the entitled process; private bytes never leave the extension.
    query[(__bridge id)kSecAttrService] = KCLLegacyService;
    query[(__bridge id)kSecAttrAccessGroup] = [KCLLegacyIdentifier stringByAppendingString:privateKey ? @".Private" : @".Public"];
    *status = SecItemCopyMatching((__bridge CFDictionaryRef)query,&result);
    NSData *data = CFBridgingRelease(result);
    if (!data) return nil;
    *status = KCLStore(privateKey,instance,data);
    if (*status == errSecDuplicateItem) {
        // Another provisioning request won the race. Read the new stored item.
        return KCLCopyData(privateKey,instance,status);
    }
    return *status == errSecSuccess ? data : nil;
}

static OSStatus KCLDeleteData(BOOL privateKey, NSString *instance) {
    NSMutableDictionary *query = KCLQuery(privateKey,instance);
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    if (status != errSecSuccess && status != errSecItemNotFound) return status;
    query[(__bridge id)kSecAttrService] = KCLLegacyService;
    query[(__bridge id)kSecAttrAccessGroup] = [KCLLegacyIdentifier stringByAppendingString:privateKey ? @".Private" : @".Public"];
    status = SecItemDelete((__bridge CFDictionaryRef)query);
    return status == errSecItemNotFound ? errSecSuccess : status;
}

// Software keys exist in the signer's memory. Only its private Keychain group
// can read their encrypted-at-rest representation; the host gets public data only.
static SecKeyRef KCLCopyBackingKey(BOOL create, NSString *instance, NSError **error) {
    OSStatus status = errSecSuccess;
    NSData *data = KCLCopyData(YES, instance, &status);
    SecKeyRef key = NULL;
    CFErrorRef failure = NULL;
    if (data) {
        key = SecKeyCreateWithData((__bridge CFDataRef)data,
            (__bridge CFDictionaryRef)@{
                (__bridge id)kSecAttrKeyType:(__bridge id)KCLBackingType(instance),
                (__bridge id)kSecAttrKeyClass:(__bridge id)kSecAttrKeyClassPrivate,
                (__bridge id)kSecAttrKeySizeInBits:KCLBackingSize(instance)}, &failure);
    } else if (status == errSecItemNotFound && create) {
        key = SecKeyCreateRandomKey((__bridge CFDictionaryRef)@{
            (__bridge id)kSecAttrKeyType:(__bridge id)KCLBackingType(instance),
            (__bridge id)kSecAttrKeySizeInBits:KCLBackingSize(instance)}, &failure);
        if (key) {
            NSData *privateData = CFBridgingRelease(SecKeyCopyExternalRepresentation(key, &failure));
            status = privateData ? KCLStore(YES, instance, privateData) : errSecInternalComponent;
            if (status != errSecSuccess) { CFRelease(key); key = NULL; }
        }
    }
    if (key && create) {
        SecKeyRef publicKey = SecKeyCopyPublicKey(key);
        NSData *publicData = publicKey ? CFBridgingRelease(SecKeyCopyExternalRepresentation(publicKey, &failure)) : nil;
        if (publicKey) CFRelease(publicKey);
        status = publicData ? KCLStore(NO, instance, publicData) : errSecInternalComponent;
        if (status != errSecSuccess) { CFRelease(key); key = NULL; }
    }
    if (failure) {
        NSError *detail = CFBridgingRelease(failure);
        if (error) *error = detail;
    } else if (!key && error) {
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
    }
    return key;
}
