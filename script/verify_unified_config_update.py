"""Compare full-Flash backups across an FPGA configuration update."""
import argparse
import hashlib
from pathlib import Path

from inspect_flash_dump import FLASH_SIZE, MCU_START, validate_xip_image


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def verify(before: bytes, after: bytes, xip_image: bytes) -> dict:
    for name, data in (('Before', before), ('After', after)):
        if len(data) != FLASH_SIZE:
            raise ValueError(f'{name} backup must be {FLASH_SIZE} bytes, got {len(data)}')
    image = validate_xip_image(xip_image)
    offset = image['offset']
    if before[offset:offset + len(xip_image)] != xip_image:
        raise ValueError('Before backup does not contain the expected XIP image')
    if before[MCU_START:] != after[MCU_START:]:
        difference = next(i for i in range(MCU_START, FLASH_SIZE)
                          if before[i] != after[i])
        raise ValueError(f'MCU user region changed at physical 0x{difference:05x}')
    changed = [i for i in range(MCU_START) if before[i] != after[i]]
    return {
        'before_flash_sha256': sha(before),
        'after_flash_sha256': sha(after),
        'mcu_region_sha256': sha(after[MCU_START:]),
        'xip_image_sha256': image['sha256'],
        'config_changed_bytes': len(changed),
        'config_first_change': f'0x{changed[0]:05x}' if changed else None,
        'config_last_change': f'0x{changed[-1]:05x}' if changed else None,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', required=True, type=Path)
    parser.add_argument('--after', required=True, type=Path)
    parser.add_argument('--xip-image', required=True, type=Path)
    args = parser.parse_args()
    result = verify(args.before.read_bytes(), args.after.read_bytes(),
                    args.xip_image.read_bytes())
    print('CONFIG_UPDATE_READBACK_OK: MCU user region unchanged')
    for key, value in result.items():
        print(f'{key}={value}')
    print('This comparison does not prove that the configuration matches the bitstream; '
          'run TD verify_spi and a no-SRAM-download power-on test separately.')


if __name__ == '__main__':
    main()
