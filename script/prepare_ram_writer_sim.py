"""Prepare the RAM writer test program for the first 32 KiB BRAM simulation bank."""
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build' / 'flash'


def to_word_hex(image: bytes) -> str:
    if not 0 < len(image) <= 32768:
        raise ValueError('RAM writer test program must fit the first 32 KiB bank')
    image += bytes(32768 - len(image))
    return ''.join(f'{word:08x}\n' for (word,) in struct.iter_unpack('<I', image))


def main() -> None:
    image = (OUT / 'ram_writer_smoke.bin').read_bytes()
    (OUT / 'ram_writer_smoke.hex').write_text(to_word_hex(image), encoding='ascii')


if __name__ == '__main__':
    main()
