import unittest
import struct
import zlib
from pathlib import Path

from inspect_flash_dump import (
    FLASH_SIZE, MCU_END, MCU_START, PROVISIONAL_START, check_xip_image,
    compare_backups, inspect,
    occupied_ranges, verify_xip_readback,
)


class FlashDumpTests(unittest.TestCase):
    def test_hardware_probe_only_reads_partition_boundaries(self):
        root = Path(__file__).resolve().parents[2]
        config = (root / 'script/openocd/probe-flash-read.cfg').read_text()
        commands = [line.strip() for line in config.splitlines()
                    if line.strip() and not line.lstrip().startswith('#')]
        self.assertEqual(commands[:4], [
            'source script/openocd/board-iotelic-ft2232h.cfg',
            'init', 'halt', 'echo {FLASH_READ_BEGIN}'])
        self.assertEqual(commands[-2:], ['echo {FLASH_READ_END}', 'shutdown'])
        self.assertTrue(all(command.startswith('mdw ') for command in commands[4:-2]))
        for address in ('0x3004fff0', '0x30050000', '0x3005fff0', '0x30060000'):
            self.assertIn(f'mdw {address} 4', commands)

    def image(self):
        payload = b'\x13\x00\x00\x00'
        return struct.pack('<4sIII', b'XIP1', len(payload),
                           0x30050010, zlib.crc32(payload)) + payload

    def test_rejects_incomplete_dump(self):
        with self.assertRaisesRegex(ValueError, 'Expected 524288 bytes'):
            inspect(b'\xff' * 4096)

    def test_cross_check_rejects_size_and_content_mismatch(self):
        before = b'\xff' * FLASH_SIZE
        compare_backups(before, before)
        with self.assertRaisesRegex(ValueError, 'Expected 524288 bytes'):
            compare_backups(before, before[:-1])
        changed = bytearray(before)
        changed[0x50000] = 0
        with self.assertRaisesRegex(ValueError, 'physical 0x50000'):
            compare_backups(before, bytes(changed))

    def test_reports_candidate_occupancy_without_declaring_it_safe(self):
        dump = bytearray(b'\xff' * FLASH_SIZE)
        dump[0] = 0x03
        dump[0x40000] = 0x01
        dump[0x50000] = 0x58
        dump[0x51000] = 0x00
        dump[0x7ffff] = 0x00
        result = inspect(bytes(dump))
        self.assertEqual(result['programmed_sectors'], [0, 0x40, 0x50, 0x51, 0x7f])
        self.assertEqual(result['config_non_ff'], 2)
        self.assertEqual(result['mcu_non_ff'], 3)
        self.assertEqual(result['candidate_non_ff'], 2)
        self.assertEqual(result['candidate_sectors'][:3], [1, 1, 0])

    def test_single_boot_partition_has_no_gap_or_overlap(self):
        self.assertEqual(MCU_START, 320 * 1024)
        self.assertEqual(MCU_END - MCU_START, 192 * 1024)
        self.assertEqual(PROVISIONAL_START, MCU_START)
        self.assertEqual(MCU_END, FLASH_SIZE)

    def test_erased_looking_dump_has_no_non_ff_bytes(self):
        result = inspect(b'\xff' * FLASH_SIZE)
        self.assertEqual(result['programmed_sectors'], [])
        self.assertEqual(result['candidate_non_ff'], 0)
        self.assertEqual(result['config_non_ff'], 0)
        self.assertEqual(result['mcu_non_ff'], 0)

    def test_occupied_sector_ranges_are_coalesced(self):
        self.assertEqual(occupied_ranges([0, 1, 3, 4, 5, 127]),
                         [(0, 1), (3, 5), (127, 127)])

    def test_xip_image_checks_header_crc_and_erased_sector(self):
        before = bytes([0xff]) * FLASH_SIZE
        plan = check_xip_image(before, self.image())
        self.assertEqual(plan['offset'], PROVISIONAL_START)
        self.assertEqual(plan['sector_end'] - plan['sector_start'], 4096)
        corrupted = bytearray(self.image())
        corrupted[-1] ^= 1
        with self.assertRaisesRegex(ValueError, 'CRC32'):
            check_xip_image(before, bytes(corrupted))

    def test_xip_rejects_occupied_target_sector(self):
        before = bytearray([0xff] * FLASH_SIZE)
        before[PROVISIONAL_START + 4095] = 0
        with self.assertRaisesRegex(ValueError, 'already contains'):
            check_xip_image(bytes(before), self.image())

    def test_xip_rejects_wrong_bootrom_address(self):
        image = bytearray(self.image())
        struct.pack_into('<I', image, 8, 0x30040010)
        with self.assertRaisesRegex(ValueError, 'BootROM slot'):
            check_xip_image(bytes([0xff]) * FLASH_SIZE, bytes(image))

    def test_full_flash_readback_detects_target_and_unrelated_changes(self):
        before = bytes([0xff]) * FLASH_SIZE
        image = self.image()
        after = bytearray(before)
        after[PROVISIONAL_START:PROVISIONAL_START + len(image)] = image
        self.assertEqual(verify_xip_readback(before, bytes(after), image)['offset'],
                         PROVISIONAL_START)
        after[PROVISIONAL_START + 2] ^= 1
        with self.assertRaisesRegex(ValueError, '0x50002'):
            verify_xip_readback(before, bytes(after), image)
        after[PROVISIONAL_START + 2] ^= 1
        after[0x100] = 0
        with self.assertRaisesRegex(ValueError, '0x00100'):
            verify_xip_readback(before, bytes(after), image)
