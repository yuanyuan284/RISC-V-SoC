"""UART fault cases and a small production-baud smoke image."""
from pathlib import Path
import struct
from uart_upload_stage3 import MAX_IMAGE, packet

ROOT = Path(__file__).resolve().parents[1]


def build_cases(smoke):
    max_image = (smoke + bytes((i % 251 for i in range(MAX_IMAGE - len(smoke) - 4)))
                 + b'EDGE')
    cases = {
        'oversize': struct.pack('<4sIII', b'RV32', 61444, 0x80000000, 0),
        'badcrc': struct.pack('<4sIII', b'RV32', 4, 0x80000000, 0) + bytes(4),
        'min_image': packet(b'\x6f\x00\x00\x00'),
        'smoke': packet(smoke),
        'max_image': packet(max_image),
        'unaligned': struct.pack('<4sIII', b'RV32', MAX_IMAGE - 1, 0x80000000, 0),
        'zero': struct.pack('<4sIII', b'RV32', 0, 0x80000000, 0),
        'wrong_entry': struct.pack('<4sIII', b'RV32', 4, 0x80000004, 0),
        'wrong_magic': struct.pack('<4sIII', b'BAD!', 4, 0x80000000, 0),
    }
    cases['max_header'] = cases['max_image'][:16]
    return cases


def main():
    out = ROOT / 'build/stage3'
    smoke = (ROOT / 'build/stage2/app_a.bin').read_bytes()
    cases = build_cases(smoke)
    assert len(cases['smoke']) == 160, 'Update smoke test length for changed Stage-2 image'
    assert len(cases['max_image']) == MAX_IMAGE + 16
    for name, frame in cases.items():
        (out / f'{name}.frame.hex').write_text(''.join(f'{b:02x}\n' for b in frame), encoding='ascii')


if __name__ == '__main__':
    main()
