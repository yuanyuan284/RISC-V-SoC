"""Make a fast-CRC copy of the XIP image for the combined RTL test only."""

import argparse
from pathlib import Path
import struct
import zlib

from prepare_flash_images import FLASH_ENTRY

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / 'build/unified/freertos_xip.xip'
DEFAULT_HEX = ROOT / 'build/unified/freertos_xip_sim_fast_crc.hex'
PREFIX_BYTES = 64
HEADER = struct.Struct('<4sIII')


def fast_crc_image(image: bytes) -> bytes:
    if len(image) < HEADER.size + PREFIX_BYTES:
        raise ValueError('XIP image is too short for the simulation CRC prefix')
    magic, length, entry, checksum = HEADER.unpack_from(image)
    payload = image[HEADER.size:]
    if (magic != b'XIP1' or entry != FLASH_ENTRY or length != len(payload) or
            length % 4 or zlib.crc32(payload) != checksum):
        raise ValueError('Source XIP image is not a valid complete production image')
    return (HEADER.pack(magic, PREFIX_BYTES, entry,
                        zlib.crc32(payload[:PREFIX_BYTES])) + payload)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=DEFAULT_SOURCE)
    parser.add_argument('--output-hex', type=Path, default=DEFAULT_HEX)
    args = parser.parse_args()
    image = fast_crc_image(args.source.read_bytes())
    args.output_hex.parent.mkdir(parents=True, exist_ok=True)
    args.output_hex.write_text(
        ''.join(f'{byte:02x}\n' for byte in image), encoding='ascii')
    print(f'SIM_FAST_BOOT_CRC prefix_bytes={PREFIX_BYTES} image_bytes={len(image)}')


if __name__ == '__main__':
    main()
