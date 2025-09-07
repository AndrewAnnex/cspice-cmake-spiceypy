#include "cspice_flavor.h"

/* Define the runtime symbol, value set via CMake */
__attribute__((used))
__attribute__((visibility("default")))
const uint8_t cspice_flavor = CSPICE_FLAVOR_ID;
