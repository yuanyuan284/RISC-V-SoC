"""Create a BRAM init and a provisional XIP image without programming Flash."""
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build' / 'flash'
FLASH_ENTRY = 0x30050010
ELF_HEADER = struct.Struct('<16sHHIIIIIHHHHHH')
PROGRAM_HEADER = struct.Struct('<IIIIIIII')


def validate_app_elf(elf: bytes, app: bytes) -> None:
    if len(elf) < ELF_HEADER.size:
        raise ValueError('Flash application ELF header is truncated')
    (ident, kind, machine, version, entry, phoff, _, flags, ehsize,
     phentsize, phnum, _, _, _) = ELF_HEADER.unpack_from(elf)
    if (ident[:7] != b'\x7fELF\x01\x01\x01' or kind != 2 or machine != 243 or
            version != 1 or flags != 0 or ehsize != ELF_HEADER.size or
            phentsize != PROGRAM_HEADER.size or not phnum or
            phoff < ehsize or phoff + phnum * phentsize > len(elf)):
        raise ValueError('Flash application is not a supported RISC-V ELF32 executable')
    if entry != FLASH_ENTRY:
        raise ValueError(f'Flash ELF entry 0x{entry:08x} differs from XIP entry 0x{FLASH_ENTRY:08x}')
    file_segments = []
    for index in range(phnum):
        ptype, offset, vaddr, paddr, filesz, memsz, permissions, _ = (
            PROGRAM_HEADER.unpack_from(elf, phoff + index * phentsize))
        if ptype != 1 or not filesz:
            continue
        if (offset + filesz > len(elf) or filesz > memsz or
                vaddr != FLASH_ENTRY or paddr != FLASH_ENTRY or
                not permissions & 1):
            raise ValueError('Flash ELF has a file-backed segment outside the XIP entry')
        file_segments.append(elf[offset:offset + filesz])
    if file_segments != [app]:
        raise ValueError('Flash ELF load segment differs from the exported application BIN')


def main():
    rom = (OUT / 'bootrom.bin').read_bytes()
    if not 0 < len(rom) <= 8192:
        raise ValueError('Flash BootROM must fit 8 KiB')
    app = (OUT / 'hello.bin').read_bytes()
    if not 0 < len(app) <= 65520:
        raise ValueError('Flash application exceeds provisional 64 KiB slot')
    validate_app_elf((OUT / 'hello.elf').read_bytes(), app)
    rom += bytes(8192 - len(rom))
    init = []
    for lane, instance in ((0, 'lo'), (2, 'hi')):
        halfwords = [int.from_bytes(rom[i + lane:i + lane + 2], 'little')
                     for i in range(0, len(rom), 4)]
        for group in range(128):
            value = sum(halfwords[group * 16 + i] << (16 * i)
                        for i in range(16))
            init.append(f'defparam {instance}.INIT_{group:02X} = ROM ? '
                        f"256'h{value:064x} : 256'b0;\n")
    (OUT / 'bootrom_init.vh').write_text(''.join(init), encoding='ascii')
    app += bytes((-len(app)) % 4)
    header = struct.pack('<4sIII', b'XIP1', len(app), FLASH_ENTRY,
                         zlib.crc32(app))
    image = header + app
    (OUT / 'hello.xip').write_bytes(image)
    (OUT / 'hello.xip.bin').write_bytes(image)
    (OUT / 'hello.xip.hex').write_text(''.join(f'{byte:02x}\n' for byte in image),
                                       encoding='ascii')
    print(f'Flash BootROM {len(rom)} bytes; XIP image {len(header) + len(app)} bytes')


if __name__ == '__main__':
    main()
