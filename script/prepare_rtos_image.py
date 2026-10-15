"""Prepare a full 64 KiB simulation RAM image from the BootROM-compatible BIN."""
from pathlib import Path
import struct
ROOT = Path(__file__).resolve().parents[1]

def main():
    output = ROOT / 'build/rtos'
    binary = (output / 'freertos.bin').read_bytes()
    if not 0 < len(binary) <= 61440:
        raise ValueError('FreeRTOS BIN exceeds the BootROM application region')
    binary += bytes(65536 - len(binary))
    (output / 'freertos.words').write_text(
        ''.join(f'{word:08x}\n' for (word,) in struct.iter_unpack('<I', binary)), encoding='ascii')

if __name__ == '__main__':
    main()
