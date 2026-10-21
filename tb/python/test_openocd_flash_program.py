"""Exercise OpenOCD's own Tcl interpreter without connecting a board."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OPENOCD = Path(r'D:\risc-v\toolchain\jtag\xpack-openocd-0.12.0-7\bin\openocd.exe')
OPENOCD = os.environ.get('OPENOCD') or str(DEFAULT_OPENOCD)


@unittest.skipUnless(shutil.which(OPENOCD), 'OpenOCD not installed')
class OpenOcdFlashProgramTests(unittest.TestCase):
    def run_script(self, old: bytes, image: bytes, offset: int,
                   confirm: bool = True, corrupt_after: bool = False,
                   require_all_backups: bool = False,
                   existing_backup: bool = False,
                   page_supported: bool = False,
                   force_byte: bool = False,
                   expected_before: bytes | None = None):
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            (temp / 'flash.bin').write_bytes(old)
            (temp / 'image.bin').write_bytes(image)
            prefix = (temp / 'backup').as_posix()
            if existing_backup:
                (temp / 'backup_60000.before.bin').write_bytes(b'KEEP')
            commands = [
                f'set mock_flash_path {{{(temp / "flash.bin").as_posix()}}}',
                f'set mock_page_supported {int(page_supported)}',
                'source tb/openocd/flash_program_mock.tcl',
                f'set flash_image {{{(temp / "image.bin").as_posix()}}}',
                f'set flash_offset 0x{offset:x}',
                f'set flash_backup_prefix {{{prefix}}}',
            ]
            if confirm:
                commands.append('set flash_confirm PROGRAM_USER_FLASH')
            if force_byte:
                commands.append('set flash_force_byte 1')
            if expected_before is not None:
                (temp / 'expected.bin').write_bytes(expected_before)
                commands.append(
                    f'set flash_expected_before_image {{{(temp / "expected.bin").as_posix()}}}')
            if corrupt_after:
                commands.append('set mock_corrupt_after 1')
            if require_all_backups:
                commands.append('set mock_require_backup_paths [list '
                                f'{{{prefix}_60000.before.bin}} '
                                f'{{{prefix}_61000.before.bin}}]')
            commands.append('source script/openocd/program-user-flash.tcl')
            result = subprocess.run(
                [OPENOCD, '-c', '; '.join(commands)], cwd=ROOT,
                capture_output=True, text=True, timeout=45, check=False,
            )
            before = {p.name: p.read_bytes() for p in temp.glob('*.before.bin')}
            after = {p.name: p.read_bytes() for p in temp.glob('*.after.bin')}
            return result, before, after

    def test_program_erased_bytes_without_erase(self):
        old = bytearray(b'\xff' * 8192)
        old[:4] = b'MCU!'
        result, before, after = self.run_script(bytes(old), b'JTAG', 0x60004)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('FLASH_SECTOR_OK sector=0x60000 erase=0 programmed=4', result.stderr)
        self.assertEqual(list(before.values()), [bytes(old[:4096])])
        expected = bytearray(old[:4096])
        expected[4:8] = b'JTAG'
        self.assertEqual(list(after.values()), [bytes(expected)])

    def test_binary_image_keeps_nul_high_bit_and_erased_byte(self):
        old = b'\xff' * 8192
        image = b'\x00\x80\xff\xfe'
        result, _, after = self.run_script(old, image, 0x60020)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('erase=0 programmed=3', result.stderr)
        expected = bytearray(old[:4096])
        expected[0x20:0x24] = image
        self.assertEqual(list(after.values()), [bytes(expected)])

    def test_page_mode_combines_64_bytes_into_four_transactions(self):
        old = b'\xff' * 8192
        image = bytes(range(64))
        result, _, after = self.run_script(old, image, 0x60020,
                                           page_supported=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('programmed=64 pages=4', result.stderr)
        expected = bytearray(old[:4096])
        expected[0x20:0x60] = image
        self.assertEqual(list(after.values()), [bytes(expected)])

    def test_force_byte_on_page_capable_writer(self):
        old = b'\xff' * 8192
        image = bytes(range(64))
        result, _, after = self.run_script(old, image, 0x60020,
                                           page_supported=True, force_byte=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('programmed=64 pages=0', result.stderr)
        self.assertIn('FLASH_WRITE_TIME_MS sector=0x60000 mode=byte', result.stderr)
        expected = bytearray(old[:4096])
        expected[0x20:0x60] = image
        self.assertEqual(list(after.values()), [bytes(expected)])

    def test_page_mode_splits_at_256_byte_boundary(self):
        old = b'\xff' * 8192
        image = b'abcdefgh'
        result, _, after = self.run_script(old, image, 0x600fc,
                                           page_supported=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('programmed=32 pages=2', result.stderr)
        expected = bytearray(old[:4096])
        expected[0xfc:0x104] = image
        self.assertEqual(list(after.values()), [bytes(expected)])

    def test_page_mode_erase_restores_untouched_bytes(self):
        old = bytearray(b'\xff' * 8192)
        old[:4] = b'MCU!'
        old[8] = 0
        result, before, after = self.run_script(bytes(old), b'XIP1', 0x60000,
                                                page_supported=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('erase=1 programmed=16 pages=1', result.stderr)
        expected = bytearray(old[:4096])
        expected[:4] = b'XIP1'
        self.assertEqual(list(before.values()), [bytes(old[:4096])])
        self.assertEqual(list(after.values()), [bytes(expected)])

    def test_page_mode_identical_image_is_noop(self):
        old = bytearray(b'\xff' * 8192)
        old[:4] = b'MCU!'
        result, before, after = self.run_script(bytes(old), b'MCU!', 0x60000,
                                                page_supported=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('FLASH_NO_CHANGE', result.stderr)
        self.assertFalse(after)
        self.assertEqual(list(before.values()), [bytes(old[:4096])])

    def test_erase_restores_untouched_bytes(self):
        old = bytearray(b'\xff' * 8192)
        old[:4] = b'MCU!'
        old[8] = 0
        result, before, after = self.run_script(bytes(old), b'XIP1', 0x60000)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('FLASH_SECTOR_OK sector=0x60000 erase=1 programmed=5', result.stderr)
        self.assertEqual(list(before.values()), [bytes(old[:4096])])
        expected = bytearray(old[:4096])
        expected[:4] = b'XIP1'
        self.assertEqual(list(after.values()), [bytes(expected)])

    def test_cross_sector_write_backs_up_both_before_programming(self):
        old = bytearray(b'\xff' * 8192)
        old[20] = 0x22
        old[4100] = 0x33
        result, before, after = self.run_script(bytes(old), b'ABCD',
                                                0x60ffe, require_all_backups=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(before), 2)
        self.assertEqual(len(after), 2)
        self.assertIn('FLASH_PROGRAM_OK offset=0x60ffe image_bytes=4', result.stderr)
        self.assertEqual(before['backup_60000.before.bin'], bytes(old[:4096]))
        self.assertEqual(before['backup_61000.before.bin'], bytes(old[4096:]))
        expected = bytearray(old)
        expected[4094:4098] = b'ABCD'
        self.assertEqual(after['backup_60000.after.bin'], bytes(expected[:4096]))
        self.assertEqual(after['backup_61000.after.bin'], bytes(expected[4096:]))

    def test_default_is_read_only(self):
        old = b'\xff' * 8192
        result, before, after = self.run_script(old, b'ABCD', 0x60000, confirm=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('FLASH_PLAN_ONLY', result.stderr)
        self.assertEqual(list(before.values()), [old[:4096]])
        self.assertFalse(after)

    def test_identical_image_does_not_claim_programming(self):
        old = bytearray(b'\xff' * 8192)
        old[:4] = b'ABCD'
        result, before, after = self.run_script(bytes(old), b'ABCD', 0x60000)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('FLASH_NO_CHANGE', result.stderr)
        self.assertNotIn('FLASH_PROGRAM_OK', result.stderr)
        self.assertEqual(list(before.values()), [bytes(old[:4096])])
        self.assertFalse(after)

    def test_rejects_configuration_partition_before_init(self):
        old = b'\xff' * 8192
        result, before, after = self.run_script(old, b'ABCD', 0x4fffe)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Image must fit wholly', result.stderr)
        self.assertFalse(before)
        self.assertFalse(after)

    def test_readback_mismatch_never_reports_success(self):
        old = b'\xff' * 8192
        result, before, after = self.run_script(
            old, b'JTAG', 0x60004, corrupt_after=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Flash readback mismatch', result.stderr)
        self.assertNotIn('FLASH_PROGRAM_OK', result.stderr)
        self.assertEqual(len(before), 1)
        self.assertEqual(len(after), 1)

    def test_rejects_flash_end_overflow_before_init(self):
        result, before, after = self.run_script(b'\xff' * 8192,
                                                 b'AB', 0x7ffff)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Image must fit wholly', result.stderr)
        self.assertFalse(before)
        self.assertFalse(after)

    def test_existing_backup_is_never_overwritten(self):
        result, before, after = self.run_script(b'\xff' * 8192,
                                                b'ABCD', 0x60000,
                                                existing_backup=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('already exists', result.stderr)
        self.assertEqual(before, {'backup_60000.before.bin': b'KEEP'})
        self.assertFalse(after)

    def test_expected_before_guard_rejects_stale_sector_without_write(self):
        old = bytearray(b'\xff' * 8192)
        old[:4] = b'MCU!'
        result, before, after = self.run_script(
            bytes(old), b'JTAG', 0x60004,
            expected_before=b'\xff' * 4096)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Expected-before mismatch', result.stderr)
        self.assertEqual(list(before.values()), [bytes(old[:4096])])
        self.assertFalse(after)

    def test_expected_before_guard_accepts_matching_sector(self):
        old = bytearray(b'\xff' * 8192)
        old[:4] = b'MCU!'
        result, _, after = self.run_script(
            bytes(old), b'JTAG', 0x60004,
            expected_before=bytes(old[:4096]))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(list(after.values())[0][4:8], b'JTAG')

    def test_full_sector_replacement_erases_old_tail(self):
        old = bytearray(b'\xff' * 8192)
        old[:24] = b'A' * 24
        image = b'B' * 16 + b'\xff' * (4096 - 16)
        result, before, after = self.run_script(
            bytes(old), image, 0x60000, page_supported=True,
            expected_before=bytes(old[:4096]))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('erase=1 programmed=16 pages=1', result.stderr)
        self.assertEqual(before['backup_60000.before.bin'], bytes(old[:4096]))
        self.assertEqual(after['backup_60000.after.bin'], image)


if __name__ == '__main__':
    unittest.main()
