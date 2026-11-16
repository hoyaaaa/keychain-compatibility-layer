#import <CryptoTokenKit/CryptoTokenKit.h>

int main(int argc, const char **argv) {
    @autoreleasepool {
        TKTokenWatcher *watcher = [TKTokenWatcher new];
        NSString *tokenID = nil;
        for (NSString *candidate in watcher.tokenIDs)
            if ([candidate hasPrefix:@"io.hoya.KeychainCompatibilityLayer.Driver"]) tokenID = candidate;
        if (!tokenID) { fprintf(stderr, "Own token is not visible\n"); return 1; }
        NSDictionary *query = @{(__bridge id)kSecClass:(__bridge id)kSecClassKey,
            (__bridge id)kSecAttrTokenID:tokenID,
            (__bridge id)kSecAttrKeyClass:(__bridge id)kSecAttrKeyClassPrivate,
            (__bridge id)kSecReturnRef:@YES};
        CFTypeRef result = NULL;
        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
        if (status != errSecSuccess) { fprintf(stderr, "Token key lookup failed: %d\n", status); return 1; }
        SecKeyRef key = (SecKeyRef)result;
        SecKeyRef publicKey = SecKeyCopyPublicKey(key);
        if (!publicKey) { fprintf(stderr, "Token public key missing\n"); CFRelease(key); return 1; }
        puts("Independent client: token discovery + key lookup + public key: PASS"); fflush(stdout);
        if (argc > 1 && strcmp(argv[1], "discover") == 0) { CFRelease(publicKey); CFRelease(key); return 0; }
        CFErrorRef error = NULL;
        CFDataRef raw = SecKeyCopyExternalRepresentation(key, &error);
        if (raw) { CFRelease(raw); fprintf(stderr, "FAIL: token allowed raw private key export\n"); CFRelease(publicKey); CFRelease(key); return 1; }
        if (error) CFRelease(error);
        puts("Token private-key export rejected: PASS"); fflush(stdout);
        BOOL decryptDenied = !SecKeyIsAlgorithmSupported(key, kSecKeyOperationTypeDecrypt, kSecKeyAlgorithmECIESEncryptionStandardX963SHA256AESGCM);
        BOOL exchangeDenied = !SecKeyIsAlgorithmSupported(key, kSecKeyOperationTypeKeyExchange, kSecKeyAlgorithmECDHKeyExchangeStandard);
        if (!decryptDenied || !exchangeDenied) { fprintf(stderr, "Unexpected token capability\n"); CFRelease(publicKey); CFRelease(key); return 1; }
        puts("Unsupported decrypt and key exchange denied: PASS"); fflush(stdout);
        if (argc > 1 && strcmp(argv[1], "inspect") == 0) { CFRelease(publicKey); CFRelease(key); return 0; }
        if (argc > 1 && strcmp(argv[1], "inspect") == 0) { CFRelease(publicKey); CFRelease(key); return 0; }
        NSData *payload = [@"Keychain Compatibility Layer cross-process self-check" dataUsingEncoding:NSUTF8StringEncoding];
        error = NULL;
        CFDataRef signature = SecKeyCreateSignature(key, kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                                   (__bridge CFDataRef)payload, &error);
        if (!signature) { fprintf(stderr, "Token sign failed: %s\n", [((__bridge NSError *)error).localizedDescription UTF8String]); if (error) CFRelease(error); CFRelease(publicKey); CFRelease(key); return 1; }
        BOOL verified = SecKeyVerifySignature(publicKey, kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
            (__bridge CFDataRef)payload, signature, NULL);
        NSData *tampered = [@"altered payload" dataUsingEncoding:NSUTF8StringEncoding];
        verified = verified && !SecKeyVerifySignature(publicKey, kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
            (__bridge CFDataRef)tampered, signature, NULL);
        CFRelease(signature); CFRelease(publicKey); CFRelease(key);
        puts(verified ? "Cross-process token signature + verification: PASS" : "Signature verification: FAIL");
        return verified ? 0 : 1;
    }
}
