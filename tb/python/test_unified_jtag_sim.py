"""Checks for combined BootROM, RTOS, and JTAG simulation evidence."""

import unittest
import struct
import zlib

from prepare_unified_sim_image import fast_crc_image, PREFIX_BYTES
from prepare_flash_images import FLASH_ENTRY
from validate_unified_jtag_sim import require_bootrom_startup


class UnifiedJtagSimTests(unittest.TestCase):
    def test_requires_ordered_boot_and_rtos_self_test(self):
        log = ('SIM_FAST_BOOT_CRC prefix_bytes=64\nBOOT FLASH\n'
               'FREERTOS START V11.1.0\n'
               'PASS unified XIP FreeRTOS preemption, queue and interrupts\n')
        require_bootrom_startup(log)
        with self.assertRaisesRegex(RuntimeError, 'missing or out of order'):
            require_bootrom_startup(log.replace('BOOT FLASH\n', ''))
        with self.assertRaisesRegex(RuntimeError, 'missing or out of order'):
            require_bootrom_startup('\n'.join(reversed(log.splitlines())))

    def test_fast_crc_header_preserves_every_payload_byte(self):
        payload = bytes(range(128))
        source = struct.pack('<4sIII', b'XIP1', len(payload), FLASH_ENTRY,
                             zlib.crc32(payload)) + payload
        fast = fast_crc_image(source)
        self.assertEqual(fast[16:], payload)
        self.assertEqual(struct.unpack_from('<4sIII', fast),
                         (b'XIP1', PREFIX_BYTES, FLASH_ENTRY,
                          zlib.crc32(payload[:PREFIX_BYTES])))
        self.assertEqual(source[16:], fast[16:])
        with self.assertRaisesRegex(ValueError, 'valid complete'):
            fast_crc_image(source[:12] + b'\x00\x00\x00\x00' + payload)
        with self.assertRaisesRegex(ValueError, 'too short'):
            fast_crc_image(source[:16])


if __name__ == '__main__':
    unittest.main()
