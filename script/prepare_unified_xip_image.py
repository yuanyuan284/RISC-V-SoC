"""Validate the FreeRTOS XIP ELF layout and package its Flash load image."""
from pathlib import Path
import struct
import zlib

from prepare_flash_images import ELF_HEADER, PROGRAM_HEADER, FLASH_ENTRY

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/unified'
FLASH_CAPACITY = 65520
RAM_BASE = 0x80000000
RAM_DATA_END = 0x80008000
RAM_CODE_BASE = 0x80008000
STACK_BOTTOM = 0x8000F000


def validate_xip_elf(elf: bytes, app: bytes) -> None:
    if not 0 < len(app) <= FLASH_CAPACITY:
        raise ValueError('FreeRTOS XIP BIN must fit the 64 KiB application slot')
    if len(elf) < ELF_HEADER.size:
        raise ValueError('FreeRTOS XIP ELF header is truncated')
    (ident, kind, machine, version, entry, phoff, _, _, ehsize,
     phentsize, phnum, _, _, _) = ELF_HEADER.unpack_from(elf)
    if (ident[:7] != b'\x7fELF\x01\x01\x01' or kind != 2 or machine != 243 or
            version != 1 or entry != FLASH_ENTRY or ehsize != ELF_HEADER.size or
            phentsize != PROGRAM_HEADER.size or not phnum or
            phoff < ehsize or phoff + phnum * phentsize > len(elf)):
        raise ValueError('FreeRTOS XIP ELF header or entry is invalid')

    ranges = []
    ram_ranges = []
    executable_entry = False
    for index in range(phnum):
        ptype, offset, vaddr, paddr, filesz, memsz, flags, _ = (
            PROGRAM_HEADER.unpack_from(elf, phoff + index * phentsize))
        if ptype != 1:
            continue
        if filesz > memsz or offset + filesz > len(elf):
            raise ValueError('Invalid XIP load segment size')
        if flags & 1:
            if vaddr == paddr and FLASH_ENTRY <= vaddr and (
                    vaddr + memsz <= FLASH_ENTRY + FLASH_CAPACITY):
                executable_entry |= vaddr <= entry < vaddr + memsz
            elif RAM_CODE_BASE <= vaddr and vaddr + memsz <= STACK_BOTTOM:
                ram_ranges.append((vaddr, vaddr + memsz))
            else:
                raise ValueError('Executable segment is outside XIP Flash and RAM code')
        else:
            if not (flags & 2 and RAM_BASE <= vaddr and
                    vaddr + memsz <= RAM_DATA_END):
                raise ValueError('XIP data/BSS segment is outside application RAM')
            if memsz:
                ram_ranges.append((vaddr, vaddr + memsz))
        if filesz:
            start = paddr - FLASH_ENTRY
            if start < 0 or start + filesz > len(app) or paddr + filesz > FLASH_ENTRY + FLASH_CAPACITY:
                raise ValueError('XIP load bytes are outside the Flash application slot')
            if app[start:start + filesz] != elf[offset:offset + filesz]:
                raise ValueError('XIP BIN differs from ELF load segment')
            ranges.append((start, start + filesz))
    if not executable_entry:
        raise ValueError('XIP entry is not inside an executable Flash segment')
    for (_, prior_end), (start, _) in zip(sorted(ram_ranges), sorted(ram_ranges)[1:]):
        if start < prior_end:
            raise ValueError('XIP RAM segments overlap')
    end = 0
    for start, stop in sorted(ranges):
        if start != end:
            raise ValueError('XIP load image has a gap or overlap')
        end = stop
    if end != len(app):
        raise ValueError('XIP BIN contains bytes outside ELF load segments')


def main() -> None:
    app = (OUT / 'freertos_xip.bin').read_bytes()
    validate_xip_elf((OUT / 'freertos_xip.elf').read_bytes(), app)
    aligned = app + bytes((-len(app)) % 4)
    image = struct.pack('<4sIII', b'XIP1', len(aligned), FLASH_ENTRY,
                        zlib.crc32(aligned)) + aligned
    (OUT / 'freertos_xip.xip').write_bytes(image)
    (OUT / 'freertos_xip.xip.hex').write_text(
        ''.join(f'{byte:02x}\n' for byte in image), encoding='ascii')
    print(f'FreeRTOS XIP image {len(image)} bytes, entry 0x{FLASH_ENTRY:08x}')


if __name__ == '__main__':
    main()
