// Runtime-only compatibility. The application's files and signature stay intact.
// Only Codex's software fallback is redirected; hardware-only requests are never
// reported as successful software keys. All unrelated Security calls pass through.
#import <CryptoTokenKit/CryptoTokenKit.h>
#import <CommonCrypto/CommonDigest.h>
#include <mach-o/dyld.h>
#include <stdlib.h>
#include "RuntimeMarker.h"
#include "CompatibilityPolicy.h"

static BOOL enabled = NO;
static BOOL diagnostic = NO;
#define TRACE(text) do { if (diagnostic) fprintf(stderr,"KCL shim: %s\n",text); } while(0)
static NSString * const TagPrefix = @"com.openai.codex.device-key.os-protected-nonextractable.";

__attribute__((constructor)) static void Initialize(void) {
    uint32_t size = 4096; char path[4096];
    if (_NSGetExecutablePath(path, &size) == 0)
        enabled = strcmp(path, "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT") == 0;
    if (enabled) KCLMarkLoaded();
    if (getenv("KCL_SHIM_TEST") && strcmp(getenv("KCL_SHIM_TEST"), "1") == 0) { enabled = YES; diagnostic = YES; }
    // Do not propagate injection to shells, build tools, helper apps or the host.
    unsetenv("DYLD_INSERT_LIBRARIES"); unsetenv("KCL_SHIM_TEST");
}

static NSData *CompatibleTag(NSDictionary *attributes) {
    if (!enabled) return nil;
    id value = attributes[(__bridge id)kSecAttrApplicationTag];
    if (![value isKindOfClass:NSData.class] || [value length] > 1024) return nil;
    NSString *tag = [[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding];
    return [tag hasPrefix:TagPrefix] ? value : nil;
}
static NSString *Instance(NSData *tag) {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(tag.bytes, (CC_LONG)tag.length, hash);
    NSMutableString *name = [NSMutableString stringWithString:@"compat-"];
    for (int i=0; i<28; i++) [name appendFormat:@"%02x",hash[i]];
    return name;
}
static BOOL Control(NSString *action, NSString *instance, NSData *tag) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:
        @"Applications/Keychain Compatibility Layer.app/Contents/MacOS/KeychainCompatibilityLayer"]];
    task.arguments = tag ? @[action, instance, [tag base64EncodedStringWithOptions:0]] : @[action,instance];
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) return NO;
    [task waitUntilExit]; return task.terminationStatus == 0;
}
static SecKeyRef CopyKey(NSString *instance, NSData *tag) {
    NSDictionary *query = @{(__bridge id)kSecClass:(__bridge id)kSecClassKey,
        (__bridge id)kSecAttrTokenID:@"io.hoya.KeychainCompatibilityLayer.Driver:key-store",
        (__bridge id)kSecAttrLabel:[NSString stringWithFormat:@"Keychain Compatibility Layer — %@ (software key)",instance],
        (__bridge id)kSecAttrKeyClass:(__bridge id)kSecAttrKeyClassPrivate,
        (__bridge id)kSecReturnRef:@YES};
    CFTypeRef ref = NULL;
    return SecItemCopyMatching((__bridge CFDictionaryRef)query, &ref) == errSecSuccess ? (SecKeyRef)ref : NULL;
}

static SecKeyRef CreateKeyImpl(CFDictionaryRef raw, CFErrorRef *error) {
    NSDictionary *attributes = (__bridge NSDictionary *)raw;
    NSDictionary *privateAttributes = attributes[(__bridge id)kSecPrivateKeyAttrs];
    NSData *tag = [privateAttributes isKindOfClass:NSDictionary.class] ? CompatibleTag(privateAttributes) : nil;
    if (!tag || attributes[(__bridge id)kSecAttrTokenID] ||
        ![attributes[(__bridge id)kSecAttrKeyType] isEqual:(__bridge id)kSecAttrKeyTypeECSECPrimeRandom] ||
        ![attributes[(__bridge id)kSecAttrKeySizeInBits] isEqual:@256]) return SecKeyCreateRandomKey(raw,error);
    TRACE("software fallback entered");
    CFErrorRef nativeError = NULL;
    SecKeyRef key = SecKeyCreateRandomKey(raw,&nativeError);
    if (key) { if (nativeError) CFRelease(nativeError); return key; }
    if (!KCLCanUseSoftwareFallback(nativeError)) {
        if (error) *error = nativeError; else if (nativeError) CFRelease(nativeError);
        return NULL;
    }
    // Preserve the actual native error if the compatibility service is unavailable.
    TRACE("native fallback failed; enrolling token");
    if (Control(@"enroll",Instance(tag),tag)) { TRACE("token enrolled; copying reference"); key = CopyKey(Instance(tag),tag); }
    TRACE("token reference lookup returned");
    if (key) { if (nativeError) CFRelease(nativeError); if (error) *error = NULL; return key; }
    if (error) *error = nativeError; else if (nativeError) CFRelease(nativeError);
    return NULL;
}
static OSStatus DeleteKeyImpl(CFDictionaryRef raw) {
    NSDictionary *query = (__bridge NSDictionary *)raw;
    NSData *tag = CompatibleTag(query);
    if (!tag || ![query[(__bridge id)kSecClass] isEqual:(__bridge id)kSecClassKey]) return SecItemDelete(raw);
    SecKeyRef key = CopyKey(Instance(tag),tag);
    if (!key) return SecItemDelete(raw);
    CFRelease(key);
    return Control(@"purge",Instance(tag),nil) ? errSecSuccess : errSecInternalComponent;
}
static OSStatus CopyMatching(CFDictionaryRef raw, CFTypeRef *result) {
    NSDictionary *query = (__bridge NSDictionary *)raw;
    NSData *tag = CompatibleTag(query);
    if (!tag || query[(__bridge id)kSecAttrTokenID] ||
        ![query[(__bridge id)kSecClass] isEqual:(__bridge id)kSecClassKey] ||
        ![query[(__bridge id)kSecReturnRef] isEqual:@YES] ||
        ![query[(__bridge id)kSecAttrKeyClass] isEqual:(__bridge id)kSecAttrKeyClassPrivate])
        return SecItemCopyMatching(raw,result);
    SecKeyRef key = CopyKey(Instance(tag),tag);
    if (!key) return SecItemCopyMatching(raw,result);
    // CTK's generic searchable attributes do not reliably reflect exportability.
    // Verify actual export rejection before satisfying Codex's non-extractable query.
    CFErrorRef exportError = NULL;
    CFDataRef data = SecKeyCopyExternalRepresentation(key,&exportError);
    if (exportError) CFRelease(exportError);
    if (data) { CFRelease(data); CFRelease(key); return errSecAuthFailed; }
    if (result) *result = key; else CFRelease(key);
    return errSecSuccess;
}

static _Thread_local BOOL creating = NO;
static _Thread_local BOOL deleting = NO;
static SecKeyRef CreateKey(CFDictionaryRef raw, CFErrorRef *error) {
    if (creating) { if (error) *error = CFErrorCreate(NULL,kCFErrorDomainOSStatus,errSecInternalComponent,NULL); return NULL; }
    creating = YES;
    @try { return CreateKeyImpl(raw,error); } @finally { creating = NO; }
}
static OSStatus DeleteKey(CFDictionaryRef raw) {
    if (deleting) return errSecInternalComponent;
    deleting = YES;
    @try { return DeleteKeyImpl(raw); } @finally { deleting = NO; }
}

__attribute__((used)) static struct { const void *replacement; const void *original; }
interpositions[] __attribute__((section("__DATA,__interpose"))) = {
    {(const void *)CreateKey,(const void *)SecKeyCreateRandomKey},
    {(const void *)CopyMatching,(const void *)SecItemCopyMatching},
    {(const void *)DeleteKey,(const void *)SecItemDelete}
};
