"""Inspect a complete EF2 internal Flash backup without changing hardware."""
import argparse
import hashlib
from pathlib import Path
import struct
import zlib

FLASH_SIZE = 0x80000
SECTOR_SIZE = 0x1000
FLASH_BASE = 0x30000000
MCU_START = 0x50000
MCU_END = FLASH_SIZE
PROVISIONAL_START = MCU_START
PROVISIONAL_END = 0x60000
GOLDEN_ADDRESS_SECTOR = 0x40000
GOLDEN_START = 0x41000


def inspect(data: bytes) -> dict:
    if len(data) != FLASH_SIZE:
        raise ValueError(f'Expected {FLASH_SIZE} bytes, got {len(data)}')
    counts = [sum(byte != 0xff for byte in data[start:start + SECTOR_SIZE])
              for start in range(0, FLASH_SIZE, SECTOR_SIZE)]
    candidate = data[PROVISIONAL_START:PROVISIONAL_END]
    return {
        'sha256': hashlib.sha256(data).hexdigest(),
        'programmed_sectors': [index for index, count in enumerate(counts) if count],
        'config_non_ff': sum(counts[:MCU_START // SECTOR_SIZE]),
        'mcu_non_ff': sum(counts[MCU_START // SECTOR_SIZE:]),
        'candidate_non_ff': sum(byte != 0xff for byte in candidate),
        'candidate_sectors': counts[PROVISIONAL_START // SECTOR_SIZE:
                                    PROVISIONAL_END // SECTOR_SIZE],
    }


def occupied_ranges(sectors: list[int]) -> list[tuple[int, int]]:
    ranges = []
    for sector in sectors:
        if ranges and sector == ranges[-1][1] + 1:
            ranges[-1] = (ranges[-1][0], sector)
        else:
            ranges.append((sector, sector))
    return ranges


def compare_backups(reference: bytes, other: bytes) -> None:
    inspect(reference)
    inspect(other)
    if reference != other:
        mismatch = next(i for i, (a, b) in
                        enumerate(zip(reference, other)) if a != b)
        raise ValueError(f'Backup differs at physical 0x{mismatch:05x}')


def validate_xip_image(image: bytes) -> dict:
    if len(image) < 20:
        raise ValueError('XIP image is too short')
    magic, length, entry, crc = struct.unpack_from('<4sIII', image)
    payload = image[16:]
    if magic != b'XIP1' or length != len(payload) or length % 4 or length > 65520:
        raise ValueError('XIP header size or magic does not match the image')
    if zlib.crc32(payload) != crc:
        raise ValueError('XIP payload CRC32 mismatch')
    offset = entry - FLASH_BASE - 16
    if offset != PROVISIONAL_START or offset + len(image) > PROVISIONAL_END:
        raise ValueError('XIP entry does not match the current BootROM slot')
    return {'offset': offset, 'sha256': hashlib.sha256(image).hexdigest()}


def check_xip_image(before: bytes, image: bytes) -> dict:
    if len(before) != FLASH_SIZE:
        raise ValueError(f'Expected {FLASH_SIZE} backup bytes, got {len(before)}')
    image_info = validate_xip_image(image)
    offset = image_info['offset']
    first_sector = offset // SECTOR_SIZE
    last_sector = (offset + len(image) - 1) // SECTOR_SIZE
    sector_start = first_sector * SECTOR_SIZE
    sector_end = (last_sector + 1) * SECTOR_SIZE
    if any(byte != 0xff for byte in before[sector_start:sector_end]):
        raise ValueError('The target erase sector already contains non-FF bytes')
    return {'offset': offset, 'sector_start': sector_start,
            'sector_end': sector_end, 'sha256': image_info['sha256']}


def verify_xip_readback(before: bytes, after: bytes, image: bytes) -> dict:
    plan = check_xip_image(before, image)
    if len(after) != FLASH_SIZE:
        raise ValueError(f'Expected {FLASH_SIZE} readback bytes, got {len(after)}')
    expected = bytearray(before)
    offset = plan['offset']
    expected[offset:offset + len(image)] = image
    if after != expected:
        mismatch = next(i for i, (actual, wanted) in
                        enumerate(zip(after, expected)) if actual != wanted)
        raise ValueError(f'Readback differs at physical 0x{mismatch:05x}')
    return plan


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dump', type=Path, help='Complete 512 KiB read-only backup')
    parser.add_argument('--image', type=Path, help='XIP image to check against the backup')
    parser.add_argument('--after', type=Path, help='Complete readback after app programming')
    parser.add_argument('--cross-check', type=Path, action='append', default=[],
                        help='Another complete backup to compare byte for byte')
    args = parser.parse_args()
    if args.after and not args.image:
        parser.error('--after requires --image')
    before = args.dump.read_bytes()
    result = inspect(before)
    for path in args.cross_check:
        compare_backups(before, path.read_bytes())
        print(f'Cross-check PASS: {path}')
    print(f'File: {args.dump}')
    print(f'Size: {FLASH_SIZE} bytes; SHA256: {result["sha256"]}')
    print(f'Sectors containing non-FF bytes: {len(result["programmed_sectors"])} / 128')
    print(f'Configuration reserve 0x00000..0x{MCU_START - 1:05x}: '
          f'{result["config_non_ff"]} non-FF bytes')
    print(f'MCU user region 0x{MCU_START:05x}..0x{MCU_END - 1:05x}: '
          f'{result["mcu_non_ff"]} non-FF bytes')
    for first, last in occupied_ranges(result['programmed_sectors']):
        print(f'  Occupied-looking: 0x{first * SECTOR_SIZE:05x}..'
              f'0x{(last + 1) * SECTOR_SIZE - 1:05x}')
    for index, count in enumerate(result['candidate_sectors']):
        address = PROVISIONAL_START + index * SECTOR_SIZE
        print(f'  0x{address:05x}..0x{address + SECTOR_SIZE - 1:05x}: '
              f'{count} non-FF bytes')
    print(f'Provisional 0x{PROVISIONAL_START:05x}..0x{PROVISIONAL_END - 1:05x}: '
          f'{result["candidate_non_ff"]} non-FF bytes')
    print(f'WARNING: 0x{GOLDEN_ADDRESS_SECTOR:05x} is the documented Dual Boot '
          f'Golden-address sector; Golden bitstream starts at 0x{GOLDEN_START:05x}. '
          'The provisional slot may still overlap a Golden image. FF bytes '
          'alone do not establish that any sector is safe to overwrite.')
    if args.image:
        image = args.image.read_bytes()
        plan = check_xip_image(before, image)
        print(f'Image: {args.image}; {len(image)} bytes; SHA256: {plan["sha256"]}')
        print(f'Target: 0x{plan["offset"]:05x}; erase-sector range '
              f'0x{plan["sector_start"]:05x}..0x{plan["sector_end"] - 1:05x} '
              'looks erased in this backup.')
        print('This is NOT permission to program: confirm the board layout and '
              'vendor erase scope first.')
        if args.after:
            verify_xip_readback(before, args.after.read_bytes(), image)
            print('PASS file-level full-Flash readback: only the intended image '
                  'bytes differ from the pre-programming backup.')


if __name__ == '__main__':
    main()
