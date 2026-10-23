import struct
import unittest
import zlib

from inspect_flash_dump import FLASH_SIZE, MCU_START
from verify_unified_config_update import verify


class UnifiedConfigUpdateTests(unittest.TestCase):
    def image(self):
        payload = b'\x13\x00\x00\x00'
        return struct.pack('<4sIII', b'XIP1', len(payload),
                           0x30050010, zlib.crc32(payload)) + payload

    def backups(self):
        before = bytearray(b'\xff' * FLASH_SIZE)
        before[MCU_START:MCU_START + len(self.image())] = self.image()
        before[0x60000] = ord('M')
        return before, bytearray(before)

    def test_config_change_preserves_every_mcu_byte(self):
        before, after = self.backups()
        after[0x1234] = 0
        after[MCU_START - 1] = 0
        result = verify(bytes(before), bytes(after), self.image())
        self.assertEqual(result['config_changed_bytes'], 2)
        self.assertEqual(result['config_first_change'], '0x01234')
        self.assertEqual(result['config_last_change'], '0x4ffff')

    def test_rejects_mcu_change_even_outside_xip_image(self):
        before, after = self.backups()
        after[0x70000] = 0
        with self.assertRaisesRegex(ValueError, 'physical 0x70000'):
            verify(bytes(before), bytes(after), self.image())

    def test_rejects_wrong_image_or_incomplete_backup(self):
        before, after = self.backups()
        before[MCU_START] = 0
        with self.assertRaisesRegex(ValueError, 'expected XIP image'):
            verify(bytes(before), bytes(after), self.image())
        before, after = self.backups()
        with self.assertRaisesRegex(ValueError, '524288'):
            verify(bytes(before), bytes(after[:-1]), self.image())

    def test_unchanged_config_is_reported_without_claiming_programming(self):
        before, after = self.backups()
        result = verify(bytes(before), bytes(after), self.image())
        self.assertEqual(result['config_changed_bytes'], 0)
        self.assertIsNone(result['config_first_change'])


if __name__ == '__main__':
    unittest.main()
