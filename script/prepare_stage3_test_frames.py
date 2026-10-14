"""UART fault cases and a small production-baud smoke image."""
from pathlib import Path
import struct
from uart_upload_stage3 import packet

ROOT = Path(__file__).resolve().parents[1]


def main():
    out = ROOT / 'build/stage3'
    cases = {
        'oversize': struct.pack('<4sIII', b'RV32', 61444, 0x80000000, 0),
        'badcrc': struct.pack('<4sIII', b'RV32', 4, 0x80000000, 0) + bytes(4),
        'smoke': packet((ROOT / 'build/stage2/app_a.bin').read_bytes()),
    }
    assert len(cases['smoke']) == 160, 'Update smoke test length for changed Stage-2 image'
    for name, frame in cases.items():
        (out / f'{name}.frame.hex').write_text(''.join(f'{b:02x}\n' for b in frame), encoding='ascii')


if __name__ == '__main__':
    main()
