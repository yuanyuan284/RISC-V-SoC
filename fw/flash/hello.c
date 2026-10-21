#include <stdint.h>

#define REG(o) (*(volatile uint32_t *)(0x40001000u + (o)))
#define FLASH_READS (*(volatile uint32_t *)0x40003000u)

volatile uint32_t stats[2];

int main(void) {
    const char *text = "HELLO,YUAN! XIP V2\r\n";
    REG(0) = 216u;
    while (*text) {
        while (REG(0x40) & 2u) {}
        REG(0x4c) = (uint8_t)*text++;
    }
    for (;;) {
        stats[0]++;
        stats[1] = FLASH_READS;
    }
}
