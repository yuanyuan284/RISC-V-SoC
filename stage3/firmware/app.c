#include <stdint.h>
#include <stdio.h>
#include <string.h>

#ifndef APP_ID
#define APP_ID 1
#endif
static volatile unsigned initialized = 1234;
static volatile unsigned zeroed;
// Exercise the upper banks without overwriting the linked C library.
static volatile uint32_t scratch[3584] __attribute__((section(".memtest")));

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    unsigned errors = zeroed != 0 || initialized != 1234;
    for (unsigned i = 0; i < 3584; ++i) scratch[i] = 0x13570000u ^ i;
    for (unsigned i = 0; i < 3584; ++i)
        if (scratch[i] != (0x13570000u ^ i)) ++errors;
    static const unsigned boundaries[] = {511, 512, 2559, 2560, 3583};
    for (unsigned i = 0; i < sizeof(boundaries) / sizeof(boundaries[0]); ++i) {
        volatile uint8_t *p = (volatile uint8_t *)&scratch[boundaries[i]];
        p[0] = 0x11; p[1] = 0x22; p[2] = 0x33; p[3] = 0x44;
        if (scratch[boundaries[i]] != 0x44332211u) ++errors;
        *(volatile uint16_t *)(p + 2) = 0xaabbu;
        if (scratch[boundaries[i]] != 0xaabb2211u) ++errors;
    }
    char buffer[80];
    int n = snprintf(buffer, sizeof(buffer), "id=%u signed=%d hex=%08x str=%.4s %%",
        APP_ID, -42, 0x1234abu, "formatting");
    if (n <= 0 || !strstr(buffer, "signed=-42 hex=001234ab str=form %")) ++errors;
    printf("APP %u: %s\r\n", APP_ID, buffer);
    printf("RAM=%u ROM=%u data=%u bss=%u errors=%u\r\n",
        65536u, 8192u, initialized, zeroed, errors);
    printf("FLOAT=%.2f\r\n", 3.25);
    printf("%s\r\n", errors ? "STAGE3 FAIL" : "STAGE3 PASS");
    return 0;
}
