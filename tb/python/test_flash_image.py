import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import prepare_flash_images
from prepare_flash_images import FLASH_ENTRY, validate_app_elf


def app_elf(app: bytes, entry: int = FLASH_ENTRY, paddr: int = FLASH_ENTRY) -> bytes:
    ident = b'\x7fELF\x01\x01\x01' + bytes(9)
    header = struct.pack('<16sHHIIIIIHHHHHH', ident, 2, 243, 1, entry,
                         52, 0, 0, 52, 32, 1, 0, 0, 0)
    segment = struct.pack('<IIIIIIII', 1, 84, FLASH_ENTRY, paddr,
                          len(app), len(app), 5, 1)
    return header + segment + app


class FlashImageTests(unittest.TestCase):
    def test_td_programming_copy_matches_xip_image(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            app = b'\x13\x00\x00\x00'
            (output / 'bootrom.bin').write_bytes(app)
            (output / 'hello.bin').write_bytes(app)
            (output / 'hello.elf').write_bytes(app_elf(app))
            with patch.object(prepare_flash_images, 'OUT', output):
                prepare_flash_images.main()
            self.assertEqual((output / 'hello.xip.bin').read_bytes(),
                             (output / 'hello.xip').read_bytes())

    def test_accepts_matching_xip_entry_and_bin(self):
        app = b'\x13\x00\x00\x00'
        validate_app_elf(app_elf(app), app)

    def test_rejects_entry_or_load_address_drift(self):
        app = b'\x13\x00\x00\x00'
        with self.assertRaisesRegex(ValueError, 'ELF entry'):
            validate_app_elf(app_elf(app, entry=0x30040010), app)
        with self.assertRaisesRegex(ValueError, 'outside the XIP entry'):
            validate_app_elf(app_elf(app, paddr=0x30040010), app)

    def test_rejects_bin_that_differs_from_elf(self):
        app = b'\x13\x00\x00\x00'
        with self.assertRaisesRegex(ValueError, 'differs from the exported'):
            validate_app_elf(app_elf(app), b'\x00\x00\x00\x00')


if __name__ == '__main__':
    unittest.main()
