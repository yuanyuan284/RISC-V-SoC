#include <stdint.h>

#include "flash_writer.h"

#define UART_REG(offset) (*(volatile uint32_t *)(0x40001000u + (offset)))

static void put_byte(uint8_t value) {
    while (UART_REG(0x40) & 2u) {}
    UART_REG(0x4c) = value;
}

int main(void) {
    static const uint8_t expected[4] = {'M', 'C', 'U', '!'};
    static const uint8_t erased = 0xffu;
    UART_REG(0) = 216u;
    int result = flash_erase_sector(0x4f000u) == FLASH_INVALID ?
                 FLASH_OK : FLASH_CONTROLLER_ERROR;
    if (result == FLASH_OK) result = flash_erase_sector(0x60000u);
    if (result == FLASH_OK)
        result = flash_program_bytes(0x60000u, expected, sizeof(expected));
    if (result == FLASH_OK)
        result = flash_program_bytes(0x60000u, &erased, 1u) == FLASH_NOT_ERASED ?
                 FLASH_OK : FLASH_CONTROLLER_ERROR;
    put_byte(result == FLASH_OK ? 'P' : 'E');
    for (;;) {}
}
