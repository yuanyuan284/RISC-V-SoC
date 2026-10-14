#include <stdint.h>

volatile uint32_t result;
volatile uint32_t initialized = 7;

__attribute__((noinline)) void debug_add(void) {
    result = initialized;
    result += 2;
}

__attribute__((noinline)) void debug_done(void) {
    __asm__ volatile ("nop");
}

int main(void) {
    debug_add();
    debug_done();
    for (;;) __asm__ volatile ("nop");
}
