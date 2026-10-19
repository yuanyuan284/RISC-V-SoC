#include <stdint.h>

#define REG(o) (*(volatile uint32_t *)(0x40001000u + (o)))

int main(void) {
    const char *text = "HELLO,YUAN!\r\n";
    REG(0) = 216u;
    while (*text) {
        while (REG(0x40) & 2u) {}
        REG(0x4c) = (uint8_t)*text++;
    }
    for (;;) {}
}
