#import "KeyStore.h"

int Audit(NSString *instance) {
    OSStatus privateStatus = errSecSuccess, publicStatus = errSecSuccess;
    NSData *privateData = KCLCopyData(YES, instance, &privateStatus);
    NSData *publicData = KCLCopyData(NO, instance, &publicStatus);
    BOOL denied = !privateData && (privateStatus == errSecMissingEntitlement || privateStatus == errSecItemNotFound);
    printf("Host can read public metadata: %s; host private-group access denied: %s (status=%d)\n",
           publicData ? "PASS" : "FAIL", denied ? "PASS" : "FAIL", privateStatus);
    return publicData && denied ? 0 : 1;
}
