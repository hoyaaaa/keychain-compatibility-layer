#import <CryptoTokenKit/CryptoTokenKit.h>
int main(int argc,const char **argv) { @autoreleasepool {
 if(argc!=2)return 2;
 NSString *instance=@(argv[1]);if(![instance hasPrefix:@"ssh-rsa-"])return 2;
 NSDictionary *query=@{(__bridge id)kSecClass:(__bridge id)kSecClassKey,(__bridge id)kSecAttrTokenID:@"io.hoya.KeychainCompatibilityLayer.Driver:key-store",(__bridge id)kSecAttrLabel:@"SSH — KCL Secretive RSA integration test",(__bridge id)kSecReturnRef:@YES};
 CFTypeRef result=NULL;OSStatus status=SecItemCopyMatching((__bridge CFDictionaryRef)query,&result);
 if(status!=errSecSuccess){printf("SSH token lookup: FAIL (%d)\n",status);return 1;}
 SecKeyRef key=(SecKeyRef)result;CFDataRef raw=SecKeyCopyExternalRepresentation(key,NULL);
 if(raw){CFRelease(raw);CFRelease(key);puts("SSH private export rejection: FAIL");return 1;}
 BOOL valid=SecKeyIsAlgorithmSupported(key,kSecKeyOperationTypeSign,kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA512)&&
 !SecKeyIsAlgorithmSupported(key,kSecKeyOperationTypeSign,kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA1)&&
 !SecKeyIsAlgorithmSupported(key,kSecKeyOperationTypeDecrypt,kSecKeyAlgorithmRSAEncryptionOAEPSHA256);
 CFRelease(key);puts(valid?"SSH private export denied; RSA-SHA512 allowed; SHA1 and decryption denied: PASS":"SSH capability policy: FAIL");return valid?0:1;
}}
