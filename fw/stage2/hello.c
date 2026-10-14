#include <stdint.h>
#ifndef MESSAGE
#ifdef APP_B
#define MESSAGE "APP B: same FPGA, new C!\r\n"
#else
#define MESSAGE "APP A: UART loaded C!\r\n"
#endif
#endif
#define REG(offset) (*(volatile uint32_t *)(0x40001000u + (offset)))
int main(void) {
    const char *p = MESSAGE;
    while (*p) {
        while (REG(0x40) & 2u) {}
        REG(0x4c) = (uint8_t)*p++;
    }
    return 0;
}
