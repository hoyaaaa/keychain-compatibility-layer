// Pure public-data encoding checks; no Keychain access or authentication.
#import "../native/integrations/secretive/SSHKeys.m"
int Enroll(TKTokenDriverConfiguration *driver, NSString *instance, NSData *tag) { return 1; }
int Purge(TKTokenDriverConfiguration *driver, NSString *instance) { return 1; }
static NSData *Bytes(const unsigned char *data,NSUInteger count) { return [NSData dataWithBytes:data length:count]; }
int main(void) { @autoreleasepool {
    TKTokenKeychainKey *key=[[TKTokenKeychainKey alloc] initWithCertificate:NULL objectID:@"ssh-test"];
    key.label=@"SSH test";key.keyType=(__bridge NSString *)kSecAttrKeyTypeRSA;
    const unsigned char valid[]={0x30,9,2,2,0,0x80,2,3,1,0,1};
    key.publicKeyData=Bytes(valid,sizeof(valid));NSDictionary *info=PublicSSHKey(key);
    assert([info[@"public_key"] hasPrefix:@"ssh-rsa "]);assert([info[@"fingerprint"] hasPrefix:@"SHA256:"]);
    NSArray *parts=[info[@"public_key"] componentsSeparatedByString:@" "];
    NSData *packet=[[NSData alloc] initWithBase64EncodedString:parts[1] options:0];
    const unsigned char expected[]={0,0,0,7,'s','s','h','-','r','s','a',0,0,0,3,1,0,1,0,0,0,2,0,0x80};
    assert([packet isEqual:Bytes(expected,sizeof(expected))]);
    key.publicKeyData=Bytes(valid,sizeof(valid)-1);assert(PublicSSHKey(key)==nil);
    const unsigned char negative[]={0x30,8,2,1,0x80,2,3,1,0,1};
    key.publicKeyData=Bytes(negative,sizeof(negative));assert(PublicSSHKey(key)==nil);
    const unsigned char indefinite[]={0x30,0x80,0,0};
    key.publicKeyData=Bytes(indefinite,sizeof(indefinite));assert(PublicSSHKey(key)==nil);
    key.keyType=(__bridge NSString *)kSecAttrKeyTypeECSECPrimeRandom;key.publicKeyData=[NSMutableData dataWithLength:65];
    assert([PublicSSHKey(key)[@"public_key"] hasPrefix:@"ecdsa-sha2-nistp256 "]);
    puts("SSH public-key packet + fingerprint + invalid DER checks: PASS");return 0;
}}
