#include <stdint.h>

#define REG(o) (*(volatile uint32_t *)(0x40001000u + (o)))
#define RAM_BASE 0x80000000u
#define MAX_IMAGE (65536u - 4096u)
#define FLASH_HEADER 0x30040000u
#define FLASH_ENTRY (FLASH_HEADER + 16u)
#define FLASH_MAGIC 0x31504958u
#define FLASH_MAX_IMAGE (65536u - 16u)

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
static void try_flash(void) {
    volatile const uint32_t *header = (volatile const uint32_t *)FLASH_HEADER;
    if (header[0] != FLASH_MAGIC) return;
    uint32_t length = header[1];
    if (!length || length > FLASH_MAX_IMAGE || (length & 3u) ||
        header[2] != FLASH_ENTRY) return;
    volatile const uint32_t *image = (volatile const uint32_t *)FLASH_ENTRY;
    uint32_t crc = 0xffffffffu;
    for (uint32_t i = 0; i < length / 4u; ++i) {
        uint32_t word = image[i];
        for (unsigned lane = 0; lane < 4; ++lane)
            crc = crc_byte(crc, (uint8_t)(word >> (8u * lane)));
    }
    if ((crc ^ 0xffffffffu) == header[3]) {
        const char *banner = "BOOT FLASH\r\n";
        while (*banner) put_byte((uint8_t)*banner++);
        ((void (*)(void))FLASH_ENTRY)();
        for (;;) {}
    }
}
void boot_main(void) {
    REG(0) = 216u;
    try_flash();
    for (;;) {
        const char *banner = "BOOT UART 64K\r\n";
        while (*banner) put_byte((uint8_t)*banner++);
        uint32_t magic = get_word(), length = get_word();
        uint32_t entry = get_word(), expected_crc = get_word();
        if (magic != 0x32335652u || !length || length > MAX_IMAGE ||
            (length & 3u) || entry != RAM_BASE) {
            put_byte('E'); continue;
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
            put_byte('E'); continue;
        }
        put_byte('G');
        ((void (*)(void))entry)();
        for (;;) {}
    }
}
