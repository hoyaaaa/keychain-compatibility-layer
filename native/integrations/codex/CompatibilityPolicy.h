#import <Security/Security.h>

// Known software-Keychain failure family only. In particular, cancellation,
// missing entitlements and malformed requests must retain their native error.
static BOOL KCLCanUseSoftwareFallback(CFErrorRef error) {
    if (!error || !CFEqual(CFErrorGetDomain(error),kCFErrorDomainOSStatus)) return NO;
    CFIndex code = CFErrorGetCode(error);
    return code == errSecAuthFailed || code == errSecItemNotFound;
}
