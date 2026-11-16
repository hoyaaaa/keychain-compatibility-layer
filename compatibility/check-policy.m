#include "../native/integrations/codex/CompatibilityPolicy.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    const CFIndex allowed[] = {errSecAuthFailed,errSecItemNotFound};
    const CFIndex denied[] = {errSecUserCanceled,errSecParam,errSecMissingEntitlement,errSecInteractionNotAllowed,errSecInternalComponent};
    assert(!KCLCanUseSoftwareFallback(NULL));
    for (unsigned i=0;i<sizeof(allowed)/sizeof(*allowed);i++) {
        CFErrorRef error=CFErrorCreate(NULL,kCFErrorDomainOSStatus,allowed[i],NULL);
        assert(KCLCanUseSoftwareFallback(error)); CFRelease(error);
    }
    for (unsigned i=0;i<sizeof(denied)/sizeof(*denied);i++) {
        CFErrorRef error=CFErrorCreate(NULL,kCFErrorDomainOSStatus,denied[i],NULL);
        assert(!KCLCanUseSoftwareFallback(error)); CFRelease(error);
    }
    CFErrorRef foreign=CFErrorCreate(NULL,CFSTR("unrelated.domain"),errSecAuthFailed,NULL);
    assert(!KCLCanUseSoftwareFallback(foreign)); CFRelease(foreign);
    puts("Known Keychain failures allowed; cancellation, malformed requests, entitlement failures and foreign domains preserved: PASS");
    return 0;
}
