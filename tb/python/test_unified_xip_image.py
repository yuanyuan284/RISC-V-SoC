import struct
import tempfile
import unittest
import zlib
from pathlib import Path
from unittest.mock import patch

import prepare_unified_xip_image as xip


CODE = b'\x13\x00\x00\x00\x73\x00\x10\x00'
DATA = b'\x12\x34\x56\x78'
RAM_CODE = b'\x13\x00\x00\x00'


def make_elf(*, entry=xip.FLASH_ENTRY, data_paddr=None, data_vaddr=xip.RAM_BASE,
             bss_vaddr=xip.RAM_BASE + 16, bss_size=16):
    if data_paddr is None:
        data_paddr = xip.FLASH_ENTRY + len(CODE)
    ident = b'\x7fELF\x01\x01\x01' + bytes(9)
    header = xip.ELF_HEADER.pack(ident, 2, 243, 1, entry, 52, 0, 0,
                                 52, 32, 3, 0, 0, 0)
    offset = 52 + 3 * 32
    segments = b''.join((
        xip.PROGRAM_HEADER.pack(1, offset, xip.FLASH_ENTRY, xip.FLASH_ENTRY,
                                len(CODE), len(CODE), 5, 4),
        xip.PROGRAM_HEADER.pack(1, offset + len(CODE), data_vaddr, data_paddr,
                                len(DATA), len(DATA), 6, 4),
        xip.PROGRAM_HEADER.pack(1, 0, bss_vaddr, data_paddr + len(DATA),
                                0, bss_size, 6, 4),
    ))
    return header + segments + CODE + DATA


def make_elf_with_ram_code(*, code_vaddr=xip.RAM_CODE_BASE, code_memsz=4):
    ident = b'\x7fELF\x01\x01\x01' + bytes(9)
    header = xip.ELF_HEADER.pack(ident, 2, 243, 1, xip.FLASH_ENTRY,
                                 52, 0, 0, 52, 32, 4, 0, 0, 0)
    offset = 52 + 4 * 32
    segments = b''.join((
        xip.PROGRAM_HEADER.pack(1, offset, xip.FLASH_ENTRY, xip.FLASH_ENTRY,
                                len(CODE), len(CODE), 5, 4),
        xip.PROGRAM_HEADER.pack(1, offset + len(CODE), code_vaddr,
                                xip.FLASH_ENTRY + len(CODE), len(RAM_CODE),
                                code_memsz, 5, 4),
        xip.PROGRAM_HEADER.pack(1, offset + len(CODE) + len(RAM_CODE),
                                xip.RAM_BASE, xip.FLASH_ENTRY + len(CODE) + len(RAM_CODE),
                                len(DATA), len(DATA), 6, 4),
        xip.PROGRAM_HEADER.pack(1, 0, xip.RAM_BASE + 16,
                                xip.FLASH_ENTRY + len(CODE) + len(RAM_CODE) + len(DATA),
                                0, 16, 6, 4),
    ))
    return header + segments + CODE + RAM_CODE + DATA


class UnifiedXipImageTests(unittest.TestCase):
    def test_two_load_regions_and_bss_are_accepted(self):
        xip.validate_xip_elf(make_elf(), CODE + DATA)

    def test_ram_executable_load_is_accepted_only_in_code_region(self):
        xip.validate_xip_elf(make_elf_with_ram_code(), CODE + RAM_CODE + DATA)
        with self.assertRaisesRegex(ValueError, 'outside XIP Flash and RAM code'):
            xip.validate_xip_elf(make_elf_with_ram_code(code_vaddr=xip.RAM_BASE),
                                 CODE + RAM_CODE + DATA)
        with self.assertRaisesRegex(ValueError, 'outside XIP Flash and RAM code'):
            xip.validate_xip_elf(make_elf_with_ram_code(
                code_vaddr=xip.STACK_BOTTOM - 4, code_memsz=8),
                CODE + RAM_CODE + DATA)

    def test_package_has_bootrom_header_and_crc(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            (out / 'freertos_xip.elf').write_bytes(make_elf())
            (out / 'freertos_xip.bin').write_bytes(CODE + DATA)
            with patch.object(xip, 'OUT', out):
                xip.main()
            image = (out / 'freertos_xip.xip').read_bytes()
            self.assertEqual((out / 'freertos_xip.xip.hex').read_text(encoding='ascii'),
                             ''.join(f'{byte:02x}\n' for byte in image))
            self.assertEqual(struct.unpack('<4sIII', image[:16]),
                             (b'XIP1', len(CODE + DATA), xip.FLASH_ENTRY,
                              zlib.crc32(CODE + DATA)))
            self.assertEqual(image[16:], CODE + DATA)

    def test_rejects_wrong_entry_or_flash_load_gap(self):
        with self.assertRaisesRegex(ValueError, 'header or entry'):
            xip.validate_xip_elf(make_elf(entry=xip.FLASH_ENTRY + 4), CODE + DATA)
        with self.assertRaisesRegex(ValueError, 'gap or overlap'):
            xip.validate_xip_elf(make_elf(data_paddr=xip.FLASH_ENTRY + 12),
                                 CODE + bytes(4) + DATA)

    def test_rejects_corrupt_bin_and_ram_stack_overlap(self):
        with self.assertRaisesRegex(ValueError, 'differs from ELF'):
            xip.validate_xip_elf(make_elf(), CODE + b'FAIL')
        with self.assertRaisesRegex(ValueError, 'outside application RAM'):
            xip.validate_xip_elf(make_elf(bss_vaddr=xip.STACK_BOTTOM - 8),
                                 CODE + DATA)

    def test_rejects_ram_segment_overlap_and_oversize_image(self):
        with self.assertRaisesRegex(ValueError, 'RAM segments overlap'):
            xip.validate_xip_elf(make_elf(bss_vaddr=xip.RAM_BASE + 2),
                                 CODE + DATA)
        with self.assertRaisesRegex(ValueError, 'application slot'):
            xip.validate_xip_elf(make_elf(), bytes(xip.FLASH_CAPACITY + 1))


if __name__ == '__main__':
    unittest.main()
