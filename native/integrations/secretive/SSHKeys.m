#import <CryptoTokenKit/CryptoTokenKit.h>
#import <CommonCrypto/CommonDigest.h>
#include <arpa/inet.h>
#import "TokenStore.h"
#import "Core.h"
#import "SecretiveIntegration.h"

static void SSHString(NSMutableData *packet, NSData *data) {
    uint32_t size = htonl((uint32_t)data.length); [packet appendBytes:&size length:4]; [packet appendData:data];
}
static NSData *DERField(NSData *data, NSUInteger *offset, unsigned char tag) {
    const unsigned char *bytes=data.bytes;NSUInteger count=data.length;
    if (*offset+2>count || bytes[(*offset)++]!=tag) return nil;
    NSUInteger length=bytes[(*offset)++];
    if (length & 0x80) {
        NSUInteger size=length&0x7f;length=0;
        if (size==0 || size>sizeof(NSUInteger) || size>count-*offset) return nil;
        for(NSUInteger i=0;i<size;i++) {if(length>NSUIntegerMax/256)return nil;length=length*256+bytes[(*offset)++];}
    }
    if(length>count-*offset)return nil;
    NSData *field=[data subdataWithRange:NSMakeRange(*offset,length)];*offset+=length;return field;
}
static NSDictionary *PublicSSHKey(TKTokenKeychainKey *item) {
    NSMutableData *packet=[NSMutableData data];NSString *algorithm=nil;
    if ([item.keyType isEqual:(__bridge NSString *)kSecAttrKeyTypeRSA]) {
        NSUInteger offset=0;NSData *sequence=DERField(item.publicKeyData,&offset,0x30);
        if(!sequence || offset!=item.publicKeyData.length)return nil;
        offset=0;NSData *modulus=DERField(sequence,&offset,0x02);NSData *exponent=DERField(sequence,&offset,0x02);
        if(!modulus.length || !exponent.length || offset!=sequence.length)return nil;
        if(((const unsigned char *)modulus.bytes)[0]&0x80 || ((const unsigned char *)exponent.bytes)[0]&0x80)return nil;
        algorithm=@"ssh-rsa";
        SSHString(packet,[algorithm dataUsingEncoding:NSUTF8StringEncoding]);SSHString(packet,exponent);SSHString(packet,modulus);
    } else if ([item.keyType isEqual:(__bridge NSString *)kSecAttrKeyTypeECSECPrimeRandom] && item.publicKeyData.length==65) {
        algorithm=@"ecdsa-sha2-nistp256";
        SSHString(packet,[algorithm dataUsingEncoding:NSUTF8StringEncoding]);SSHString(packet,[@"nistp256" dataUsingEncoding:NSUTF8StringEncoding]);SSHString(packet,item.publicKeyData);
    } else return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(packet.bytes,(CC_LONG)packet.length,digest);
    NSString *fingerprint = [[[NSData dataWithBytes:digest length:sizeof(digest)] base64EncodedStringWithOptions:0] stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return @{@"id":item.objectID,@"name":item.label,@"public_key":[NSString stringWithFormat:@"%@ %@ %@",algorithm,[packet base64EncodedStringWithOptions:0],item.label],@"fingerprint":[@"SHA256:" stringByAppendingString:fingerprint]};
}
int CreateSSHKey(TKTokenDriverConfiguration *driver, NSString *name) {
    if (name.length == 0 || name.length > 80 || [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
        fprintf(stderr,"Key name must be 1–80 characters without control characters.\n");return 2;
    }
    NSString *instance = [@"ssh-rsa-" stringByAppendingString:NSUUID.UUID.UUIDString.lowercaseString];
    NSData *tag = [[@"io.hoya.KeychainCompatibilityLayer.ssh." stringByAppendingString:instance] dataUsingEncoding:NSUTF8StringEncoding];
    if (Enroll(driver,instance,tag) != 0) { Purge(driver,instance); return 1; }
    TKTokenKeychainKey *item = KCLPublishedKey(driver,instance);
    item.label = [@"SSH — " stringByAppendingString:name];
    TKTokenConfiguration *store = driver.tokenConfigurations[KCLStoreInstance];
    NSMutableArray *items = [NSMutableArray array];
    for (TKTokenKeychainItem *candidate in store.keychainItems)
        [items addObject:[candidate.objectID isEqual:instance] ? item : candidate];
    store.keychainItems = items;
    NSDictionary *info = PublicSSHKey(item);if (!info) {Purge(driver,instance);return 1;}
    NSData *json=[NSJSONSerialization dataWithJSONObject:info options:0 error:nil];
    puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);return 0;
}
int ListSSHKeys(TKTokenDriverConfiguration *driver) {
    NSMutableArray *keys=[NSMutableArray array];
    for (TKTokenKeychainItem *candidate in driver.tokenConfigurations[KCLStoreInstance].keychainItems) {
        if ([candidate isKindOfClass:TKTokenKeychainKey.class] && [candidate.objectID isKindOfClass:NSString.class] && [(NSString *)candidate.objectID hasPrefix:@"ssh-"]) {
            NSDictionary *info=PublicSSHKey((TKTokenKeychainKey *)candidate);if(info)[keys addObject:info];
        }
    }
    NSData *json=[NSJSONSerialization dataWithJSONObject:keys options:0 error:nil];puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);return 0;
}
