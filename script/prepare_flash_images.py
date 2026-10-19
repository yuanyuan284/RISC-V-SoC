"""Create a BRAM init and a provisional XIP image without programming Flash."""
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build' / 'flash'
FLASH_ENTRY = 0x30040010


def main():
    rom = (OUT / 'bootrom.bin').read_bytes()
    if not 0 < len(rom) <= 8192:
        raise ValueError('Flash BootROM must fit 8 KiB')
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
    app = (OUT / 'hello.bin').read_bytes()
    if not 0 < len(app) <= 65520:
        raise ValueError('Flash application exceeds provisional 64 KiB slot')
    app += bytes((-len(app)) % 4)
    header = struct.pack('<4sIII', b'XIP1', len(app), FLASH_ENTRY,
                         zlib.crc32(app))
    image = header + app
    (OUT / 'hello.xip').write_bytes(image)
    (OUT / 'hello.xip.hex').write_text(''.join(f'{byte:02x}\n' for byte in image),
                                       encoding='ascii')
    print(f'Flash BootROM {len(rom)} bytes; XIP image {len(header) + len(app)} bytes')


if __name__ == '__main__':
    main()
