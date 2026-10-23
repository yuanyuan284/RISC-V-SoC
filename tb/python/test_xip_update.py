import struct
import unittest
import zlib

from inspect_flash_dump import FLASH_SIZE, PROVISIONAL_START, SECTOR_SIZE
from plan_xip_update import make_plan, verify_after


def image(payload: bytes) -> bytes:
    return struct.pack('<4sIII', b'XIP1', len(payload), 0x30050010,
                       zlib.crc32(payload)) + payload


class XipUpdateTests(unittest.TestCase):
    def setUp(self):
        self.old = image(b'OLD!')
        self.new = image(b'NEW!' + b'\x13\x00\x00\x00')
        self.before = bytearray(b'\xff' * FLASH_SIZE)
        self.before[0x100] = 0x42
        self.before[PROVISIONAL_START:PROVISIONAL_START + len(self.old)] = self.old

    def test_update_changes_only_one_sector_and_clears_old_tail(self):
        plan = make_plan(bytes(self.before), self.old, self.new)
        self.assertEqual(len(plan['old_sector']), SECTOR_SIZE)
        self.assertEqual(len(plan['new_sector']), SECTOR_SIZE)
        self.assertEqual(plan['new_sector'][:len(self.new)], self.new)
        self.assertEqual(plan['new_sector'][len(self.new):],
                         b'\xff' * (SECTOR_SIZE - len(self.new)))
        verify_after(plan, plan['expected_flash'])
        self.assertEqual(plan['expected_flash'][0x100], 0x42)

    def test_rejects_stale_backup_and_non_erased_tail(self):
        with self.assertRaisesRegex(ValueError, 'does not match old image'):
            make_plan(bytes(self.before), image(b'ELSE'), self.new)
        self.before[PROVISIONAL_START + SECTOR_SIZE - 1] = 0
        with self.assertRaisesRegex(ValueError, 'does not match old image'):
            make_plan(bytes(self.before), self.old, self.new)

    def test_rejects_identical_corrupt_or_slot_overflow_image(self):
        with self.assertRaisesRegex(ValueError, 'identical'):
            make_plan(bytes(self.before), self.old, self.old)
        corrupt = bytearray(self.new)
        corrupt[-1] ^= 1
        with self.assertRaisesRegex(ValueError, 'CRC32'):
            make_plan(bytes(self.before), self.old, bytes(corrupt))
        with self.assertRaisesRegex(ValueError, 'XIP header size'):
            make_plan(bytes(self.before), self.old, image(b'\x13' * 65524))

    def test_four_sector_update_preserves_other_flash_and_erased_tail(self):
        large = image(b'R' * (3 * SECTOR_SIZE + 100))
        plan = make_plan(bytes(self.before), self.old, large)
        self.assertEqual(plan['manifest']['sector_count'], 4)
        self.assertEqual(plan['manifest']['physical_sector'], '0x50000..0x53fff')
        self.assertEqual(len(plan['old_sector']), 4 * SECTOR_SIZE)
        self.assertEqual(plan['new_sector'][:len(large)], large)
        self.assertEqual(plan['new_sector'][len(large):],
                         b'\xff' * (4 * SECTOR_SIZE - len(large)))
        self.assertEqual(plan['expected_flash'][0x100], 0x42)
        self.assertEqual(plan['expected_flash'][0x54000:], self.before[0x54000:])
        verify_after(plan, plan['expected_flash'])

    def test_four_sector_update_rejects_unexpected_old_tail(self):
        self.before[PROVISIONAL_START + 2 * SECTOR_SIZE] = 0
        with self.assertRaisesRegex(ValueError, 'does not match old image'):
            make_plan(bytes(self.before), self.old,
                      image(b'R' * (3 * SECTOR_SIZE + 100)))

    def test_full_readback_rejects_unrelated_change(self):
        plan = make_plan(bytes(self.before), self.old, self.new)
        after = bytearray(plan['expected_flash'])
        after[0x100] ^= 1
        with self.assertRaisesRegex(ValueError, '0x00100'):
            verify_after(plan, bytes(after))
