#import <CryptoTokenKit/CryptoTokenKit.h>

// Public provisioning API. Private material stays in the token extension.
int Enroll(TKTokenDriverConfiguration *driver, NSString *instance, NSData *externalTag);
int Audit(NSString *instance);
int Purge(TKTokenDriverConfiguration *driver, NSString *instance);
