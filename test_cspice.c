#include "SpiceUsr.h"
#include <stdio.h>


int main(void)
{
    SpiceDouble et;
    /* Call b1900_c to get the Julian Date corresponding to Besselian date 1900.0. */
    et = b1900_c();
    printf("b1900_c returned: %f\n", et);
    return 0;
}
