"""Prepare a sector-aligned XIP replacement and verify full-Flash readback."""
import argparse
import hashlib
import json
from pathlib import Path

from inspect_flash_dump import FLASH_SIZE, PROVISIONAL_START, SECTOR_SIZE, validate_xip_image


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def make_plan(before: bytes, old_image: bytes, new_image: bytes) -> dict:
    if len(before) != FLASH_SIZE:
        raise ValueError(f'Expected {FLASH_SIZE} backup bytes, got {len(before)}')
    old_info = validate_xip_image(old_image)
    new_info = validate_xip_image(new_image)
    if old_info['offset'] != PROVISIONAL_START or new_info['offset'] != PROVISIONAL_START:
        raise ValueError('XIP image must start at the current BootROM slot')
    sector_count = (max(len(old_image), len(new_image)) + SECTOR_SIZE - 1) // SECTOR_SIZE
    region_size = sector_count * SECTOR_SIZE
    old_sector = before[PROVISIONAL_START:PROVISIONAL_START + region_size]
    if old_sector != old_image + b'\xff' * (region_size - len(old_image)):
        raise ValueError('Backup XIP region does not match old image plus erased tail')
    if old_image == new_image:
        raise ValueError('New XIP image is identical to the current image')
    new_sector = new_image + b'\xff' * (region_size - len(new_image))
    expected = (before[:PROVISIONAL_START] + new_sector +
                before[PROVISIONAL_START + region_size:])
    return {
        'old_sector': old_sector,
        'new_sector': new_sector,
        'expected_flash': expected,
        'manifest': {
            'physical_sector': (f'0x{PROVISIONAL_START:05x}..'
                                f'0x{PROVISIONAL_START + region_size - 1:05x}'),
            'sector_count': sector_count,
            'before_flash_sha256': sha(before),
            'old_image_sha256': sha(old_image),
            'new_image_sha256': sha(new_image),
            'old_sector_sha256': sha(old_sector),
            'new_sector_sha256': sha(new_sector),
            'expected_flash_sha256': sha(expected),
            'changed_bytes': sum(a != b for a, b in zip(before, expected)),
        },
    }


def verify_after(plan: dict, after: bytes) -> None:
    if len(after) != FLASH_SIZE:
        raise ValueError(f'Expected {FLASH_SIZE} readback bytes, got {len(after)}')
    expected = plan['expected_flash']
    if after != expected:
        mismatch = next(i for i, (a, b) in enumerate(zip(after, expected)) if a != b)
        raise ValueError(f'Flash readback differs at physical 0x{mismatch:05x}')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', type=Path, required=True)
    parser.add_argument('--old-image', type=Path, required=True)
    parser.add_argument('--new-image', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path)
    parser.add_argument('--after', type=Path)
    args = parser.parse_args()
    if bool(args.output_dir) == bool(args.after):
        parser.error('Choose exactly one of --output-dir (plan) or --after (verify)')
    plan = make_plan(args.before.read_bytes(), args.old_image.read_bytes(),
                     args.new_image.read_bytes())
    if args.after:
        verify_after(plan, args.after.read_bytes())
        print('XIP_UPDATE_VERIFY_OK full 512 KiB matches planned image')
        return
    args.output_dir.mkdir(parents=True, exist_ok=False)
    suffix = 'sector' if plan['manifest']['sector_count'] == 1 else 'sectors'
    (args.output_dir / f'old_{suffix}.bin').write_bytes(plan['old_sector'])
    (args.output_dir / f'new_{suffix}.bin').write_bytes(plan['new_sector'])
    (args.output_dir / 'manifest.json').write_text(
        json.dumps(plan['manifest'], indent=2) + '\n', encoding='ascii')
    print(f'XIP_UPDATE_PLAN_OK {args.output_dir}')
    print(json.dumps(plan['manifest'], sort_keys=True))


if __name__ == '__main__':
    main()
