#include "flash_writer.h"

#define FLASH_USER_START 0x50000u
#define FLASH_SIZE 0x80000u
#define FLASH_MMIO 0x40004000u
#define FLASH_READ_BASE 0x30000000u
#define FLASH_BUSY 1u
#define FLASH_DONE 2u
#define FLASH_ERROR 4u
#define FLASH_PAGE_SUPPORTED 0x80u
#define FLASH_PAGE_CHUNK 16u
#define FLASH_WAIT_POLLS 25000000u

static volatile uint32_t *const writer = (volatile uint32_t *)FLASH_MMIO;

static uint8_t read_byte(uint32_t offset) {
    volatile const uint32_t *word =
        (volatile const uint32_t *)(FLASH_READ_BASE + (offset & ~3u));
    return (uint8_t)(*word >> (8u * (offset & 3u)));
}

static int wait_done(void) {
    for (uint32_t polls = 0; polls < FLASH_WAIT_POLLS; ++polls) {
        uint32_t status = writer[3];
        if (status & FLASH_ERROR) return FLASH_CONTROLLER_ERROR;
        if (!(status & FLASH_BUSY))
            return (status & FLASH_DONE) ? FLASH_OK : FLASH_CONTROLLER_ERROR;
    }
    return FLASH_CONTROLLER_ERROR;
}

int flash_erase_sector(uint32_t offset) {
    if (offset < FLASH_USER_START || offset >= FLASH_SIZE ||
        (offset & 0xfffu)) return FLASH_INVALID;
    writer[0] = offset;
    writer[2] = 1u;
    int result = wait_done();
    if (result != FLASH_OK) return result;
    for (uint32_t i = 0; i < 4096u; ++i)
        if (read_byte(offset + i) != 0xffu) return FLASH_VERIFY_FAILED;
    return FLASH_OK;
}

int flash_program_bytes(uint32_t offset, const uint8_t *bytes, size_t length) {
    if (!bytes || offset < FLASH_USER_START || offset >= FLASH_SIZE ||
        length == 0 || length > FLASH_SIZE - offset) return FLASH_INVALID;
    for (size_t i = 0; i < length; ++i)
        if ((read_byte(offset + (uint32_t)i) & bytes[i]) != bytes[i])
            return FLASH_NOT_ERASED;
    const int page_supported = (writer[3] & FLASH_PAGE_SUPPORTED) != 0;
    for (size_t i = 0; i < length;) {
        size_t chunk = 1;
        uint32_t address = offset + (uint32_t)i;
        if (page_supported) {
            chunk = length - i;
            if (chunk > FLASH_PAGE_CHUNK) chunk = FLASH_PAGE_CHUNK;
            size_t page_room = 256u - (address & 0xffu);
            if (chunk > page_room) chunk = page_room;
        }
        int changed = 0;
        for (size_t j = 0; j < chunk; ++j)
            if (read_byte(address + (uint32_t)j) != bytes[i + j]) changed = 1;
        if (changed) {
            writer[0] = address;
            if (page_supported) {
                writer[2] = 3u;
                for (size_t j = 0; j < chunk; ++j) writer[1] = bytes[i + j];
                writer[2] = 4u;
            } else {
                writer[1] = bytes[i];
                writer[2] = 2u;
            }
            int result = wait_done();
            if (result != FLASH_OK) return result;
            for (size_t j = 0; j < chunk; ++j)
                if (read_byte(address + (uint32_t)j) != bytes[i + j])
                    return FLASH_VERIFY_FAILED;
        }
        i += chunk;
    }
    return FLASH_OK;
}
