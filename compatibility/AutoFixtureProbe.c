#include "../native/core/RuntimeMarker.h"
__attribute__((constructor)) static void loaded(void) { KCLMarkLoaded(); }
