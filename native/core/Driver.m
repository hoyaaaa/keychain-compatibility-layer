#import <CryptoTokenKit/CryptoTokenKit.h>
#import <LocalAuthentication/LocalAuthentication.h>
#import "KeyStore.h"
#import "TokenStore.h"

static NSError *Failure(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"io.hoya.KeychainCompatibilityLayer" code:code
                          userInfo:@{NSLocalizedDescriptionKey:message}];
}

static SecKeyAlgorithm KCLSignatureAlgorithm(TKTokenKeyAlgorithm *algorithm, BOOL rsa) {
    if (!rsa) return [algorithm isAlgorithm:kSecKeyAlgorithmECDSASignatureDigestX962] ? kSecKeyAlgorithmECDSASignatureDigestX962 : NULL;
    // Security may hash/pad RSA before calling CTK. Only accept SHA-512 chains.
    if (![algorithm supportsAlgorithm:kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA512] &&
        ![algorithm supportsAlgorithm:kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA512]) return NULL;
    for (id candidate in @[(__bridge id)kSecKeyAlgorithmRSASignatureRaw,(__bridge id)kSecKeyAlgorithmRSASignatureDigestPKCS1v15Raw,(__bridge id)kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA512])
        if ([algorithm isAlgorithm:(__bridge SecKeyAlgorithm)candidate]) return (__bridge SecKeyAlgorithm)candidate;
    return NULL;
}

@interface KeychainCompatibilityLayerSession : TKTokenSession<TKTokenSessionDelegate>
@end
@implementation KeychainCompatibilityLayerSession
- (instancetype)initWithToken:(TKToken *)token {
    if ((self = [super initWithToken:token])) self.delegate = self;
    return self;
}
- (BOOL)tokenSession:(TKTokenSession *)session supportsOperation:(TKTokenOperation)operation
           usingKey:(TKTokenObjectID)objectID algorithm:(TKTokenKeyAlgorithm *)algorithm {
    BOOL known = NO;
    if ([self.token.configuration.instanceID isEqual:KCLStoreInstance]) {
        for (TKTokenKeychainItem *item in self.token.configuration.keychainItems)
            if ([item.objectID isEqual:objectID]) known = YES;
    } else known = [objectID isEqual:@"signing-key"];
    if (!known || ![objectID isKindOfClass:NSString.class]) return NO;
    NSString *instance = [self.token.configuration.instanceID isEqual:KCLStoreInstance] ? (NSString *)objectID : self.token.configuration.instanceID;
    return operation == TKTokenOperationSignData && KCLSignatureAlgorithm(algorithm,[instance hasPrefix:@"ssh-rsa-"]) != NULL;
}
- (NSData *)tokenSession:(TKTokenSession *)session signData:(NSData *)data
                usingKey:(TKTokenObjectID)objectID algorithm:(TKTokenKeyAlgorithm *)algorithm
                   error:(NSError **)error {
    if (![self tokenSession:session supportsOperation:TKTokenOperationSignData usingKey:objectID algorithm:algorithm]) {
        if (error) *error = Failure(1, @"Unsupported key or signature algorithm");
        return nil;
    }
    LAContext *context = [LAContext new];
    NSError *authError = nil;
    if (![context canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:&authError]) {
        if (error) *error = authError;
        return nil;
    }
    dispatch_semaphore_t ready = dispatch_semaphore_create(0);
    __block BOOL allowed = NO;
    __block NSError *resultError = nil;
    [context evaluatePolicy:LAPolicyDeviceOwnerAuthentication
            localizedReason:@"Allow this application to sign with Keychain Compatibility Layer"
                      reply:^(BOOL success, NSError *failure) {
        allowed = success; resultError = failure; dispatch_semaphore_signal(ready);
    }];
    if (dispatch_semaphore_wait(ready, dispatch_time(DISPATCH_TIME_NOW, 120*NSEC_PER_SEC)) != 0) {
        [context invalidate];
        if (error) *error = Failure(2, @"Authentication timed out");
        return nil;
    }
    if (!allowed) { if (error) *error = resultError ?: Failure(3, @"Authentication denied"); return nil; }
    SecKeyRef ref = KCLCopyBackingKey(NO, [session.token.configuration.instanceID isEqual:KCLStoreInstance] ? (NSString *)objectID : session.token.configuration.instanceID, error);
    if (!ref) return nil;
    CFErrorRef signError = NULL;
    NSString *instance = [session.token.configuration.instanceID isEqual:KCLStoreInstance] ? (NSString *)objectID : session.token.configuration.instanceID;
    SecKeyAlgorithm signing = KCLSignatureAlgorithm(algorithm,[instance hasPrefix:@"ssh-rsa-"]);
    CFDataRef signature = SecKeyCreateSignature((SecKeyRef)ref, signing,
                                               (__bridge CFDataRef)data, &signError);
    CFRelease(ref);
    if (!signature) { if (error) *error = CFBridgingRelease(signError); return nil; }
    return CFBridgingRelease(signature);
}
@end

@interface KeychainCompatibilityLayer : TKToken<TKTokenDelegate>
@end
@implementation KeychainCompatibilityLayer
- (instancetype)initWithTokenDriver:(TKTokenDriver *)driver instanceID:(TKTokenInstanceID)instanceID {
    if ((self = [super initWithTokenDriver:driver instanceID:instanceID])) self.delegate = self;
    return self;
}
- (TKTokenSession *)token:(TKToken *)token createSessionWithError:(NSError **)error {
    return [[KeychainCompatibilityLayerSession alloc] initWithToken:token];
}
@end

@interface KeychainCompatibilityLayerDriver : TKTokenDriver<TKTokenDriverDelegate>
@end

@implementation KeychainCompatibilityLayerDriver
- (instancetype)init {
    if ((self = [super init])) self.delegate = self;
    return self;
}
- (TKToken *)tokenDriver:(TKTokenDriver *)driver
  tokenForConfiguration:(TKTokenConfiguration *)configuration error:(NSError **)error {
    if ([configuration.instanceID isEqual:KCLStoreInstance]) return [[KeychainCompatibilityLayer alloc] initWithTokenDriver:driver instanceID:configuration.instanceID];
    if ([configuration.configurationData isEqual:[@"purge-key" dataUsingEncoding:NSUTF8StringEncoding]]) {
        OSStatus status = KCLDeleteData(YES, configuration.instanceID);
        if (status == errSecSuccess || status == errSecItemNotFound)
            KCLDeleteData(NO, configuration.instanceID);
        if (error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecItemNotFound userInfo:nil];
        return nil;
    }
    SecKeyRef key = KCLCopyBackingKey(YES, configuration.instanceID, error);
    if (!key) {
        NSLog(@"KCL key provisioning failed: %@", error ? *error : nil);
        return nil;
    }
    CFRelease(key);
    return [[KeychainCompatibilityLayer alloc] initWithTokenDriver:driver instanceID:configuration.instanceID];
}
@end
