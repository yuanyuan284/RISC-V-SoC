"""Derive physical ROM init and simulation files from objcopy BINs."""
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build' / 'stage3'

def words(data):
    data += bytes((-len(data)) % 4)
    return ''.join(f'{w:08x}\n' for w, in struct.iter_unpack('<I', data))

def main():
    rom = (OUT / 'bootrom.bin').read_bytes()
    if not 0 < len(rom) <= 8192:
        raise ValueError('BootROM must fit 8 KiB')
    rom += bytes(8192 - len(rom))
    (OUT / 'bootrom.words.hex').write_text(words(rom), encoding='ascii')
    init = []
    for lane, instance in [(0, 'lo'), (2, 'hi')]:
        halfwords = [int.from_bytes(rom[i+lane:i+lane+2], 'little')
                     for i in range(0, len(rom), 4)]
        for group in range(128):
            value = sum(halfwords[group * 16 + i] << (16 * i) for i in range(16))
            init.append(f'defparam {instance}.INIT_{group:02X} = ROM ? 256\'h{value:064x} : 256\'b0;\n')
    (OUT / 'bootrom_init.vh').write_text(''.join(init), encoding='ascii')
    for app in ['app_a', 'app_b']:
        payload = (OUT / f'{app}.bin').read_bytes()
        if not 0 < len(payload) <= 61440:
            raise ValueError('Application must fit RAM below stack')
        payload += bytes((-len(payload)) % 4)
        frame = struct.pack('<4sIII', b'RV32', len(payload), 0x80000000,
                            zlib.crc32(payload)) + payload
        (OUT / f'{app}.frame.hex').write_text(''.join(f'{b:02x}\n' for b in frame), encoding='ascii')
        (OUT / f'{app}.length.vh').write_text(str(len(frame)), encoding='ascii')
        (OUT / f'{app}.words.hex').write_text(words(payload), encoding='ascii')
        print(f'{app}: {len(payload)} payload bytes, {len(frame)} frame bytes')

if __name__ == '__main__':
    main()
