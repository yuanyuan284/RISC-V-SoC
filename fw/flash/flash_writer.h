#ifndef FLASH_WRITER_H
#define FLASH_WRITER_H

#include <stddef.h>
#include <stdint.h>

enum {
    FLASH_OK = 0,
    FLASH_INVALID = -1,
    FLASH_CONTROLLER_ERROR = -2,
    FLASH_NOT_ERASED = -3,
    FLASH_VERIFY_FAILED = -4
};

// Call these only from RAM-resident code. Offsets are physical Flash byte offsets.
int flash_erase_sector(uint32_t offset);
int flash_program_bytes(uint32_t offset, const uint8_t *bytes, size_t length);

#endif
