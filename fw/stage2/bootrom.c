#include <stdint.h>

#define REG(offset) (*(volatile uint32_t *)(0x40001000u + (offset)))
#define RAM_BASE 0x80000000u
#define MAX_IMAGE 896u

static void put_byte(uint8_t byte) {
    while (REG(0x40) & 2u) {}
    REG(0x4c) = byte;
}

static uint8_t get_byte(void) {
    while (REG(0x80) & 1u) {}
    return (uint8_t)REG(0x8c);
}

static uint32_t get_word(void) {
    uint32_t value = 0;
    for (unsigned i = 0; i < 4; ++i) {
        value |= (uint32_t)get_byte() << (8u * i);
        put_byte('A');
    }
    return value;
}

static uint32_t crc_byte(uint32_t crc, uint8_t byte) {
    crc ^= byte;
    for (unsigned i = 0; i < 8; ++i)
        crc = (crc >> 1) ^ (0xedb88320u & (0u - (crc & 1u)));
    return crc;
}

void boot_main(void) {
    REG(0) = 216u;
    for (;;) {
        const char *banner = "BOOT UART\r\n";
        while (*banner) put_byte((uint8_t)*banner++);
        uint32_t magic = get_word();
        uint32_t length = get_word();
        uint32_t entry = get_word();
        uint32_t expected_crc = get_word();
        if (magic != 0x32335652u || !length || length > MAX_IMAGE ||
                (length & 3u) || entry != RAM_BASE) {
            put_byte('E');
            continue;
        }
        put_byte('H');
        volatile uint8_t *ram = (volatile uint8_t *)RAM_BASE;
        uint32_t crc = 0xffffffffu;
        for (uint32_t i = 0; i < length; ++i) {
            uint8_t byte = get_byte();
            ram[i] = byte;
            crc = crc_byte(crc, byte);
            put_byte('A');
        }
        if ((crc ^ 0xffffffffu) != expected_crc) {
            put_byte('E');
            continue;
        }
        put_byte('G');
        // One application per hardware reset: RAM has not been fetched before.
        // Applications must not jump back here without invalidating I-cache.
        ((void (*)(void))entry)();
        for (;;) {}
    }
}
