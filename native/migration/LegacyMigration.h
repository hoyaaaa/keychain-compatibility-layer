// Historical names are isolated here solely to import existing installations.
// They are not used for new keys, runtime identities, or display names.
#import <Foundation/Foundation.h>
static NSString * const KCLLegacyIdentifier = @"io.hoya.FakeSecureEnclave";
static NSString * const KCLLegacyService = @"Fake Secure Enclave";

@class TKTokenDriverConfiguration;
int MigrateLegacy(TKTokenDriverConfiguration *driver);
