"""Check that segmented Flash backups are published only after clean reads."""

from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from backup_flash_segmented import BackupError, FLASH_BASE, backup
from inspect_flash_dump import FLASH_SIZE


class FakeOpenOcd:
    def __init__(self, flash: bytes, failures=None):
        self.flash = flash
        self.failures = failures or {}
        self.calls = []

    def __call__(self, command, **kwargs):
        self.calls.append(command)
        number = len(self.calls)
        match = re.search(r"dump_image \{([^}]+)\} (0x[0-9a-f]+) (0x[0-9a-f]+)",
                          command[-1])
        if not match:
            raise AssertionError(command)
        path = Path(match.group(1))
        offset = int(match.group(2), 16) - FLASH_BASE
        size = int(match.group(3), 16)
        data = self.flash[offset:offset + size]
        failure = self.failures.get(number)
        if failure == "timeout":
            raise subprocess.TimeoutExpired(command, kwargs["timeout"])
        if failure == "short":
            data = data[:-1]
        if failure == "mismatch":
            data = bytes([data[0] ^ 1]) + data[1:]
        path.write_bytes(data)
        log = ("Info : JTAG tap: soc.cpu tap/device found: 0x10002fff\n"
               "Info : [soc.cpu] Examination succeed\n")
        if failure == "error":
            log += "Error: failed read at 0x16, status=2\n"
        return subprocess.CompletedProcess(command, 0, "", log)


class FlashSegmentedBackupTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.temp = Path(self.directory.name)
        self.config = self.temp / "board.cfg"
        self.bitstream = self.temp / "stage3_flash.bit"
        self.config.write_text("mock", encoding="ascii")
        self.bitstream.write_bytes(b"mock")
        flash = bytearray(b"\xff" * FLASH_SIZE)
        flash[0:4] = b"CONF"
        flash[0x50000:0x50004] = b"XIP1"
        flash[0x60000:0x60004] = b"MCU!"
        self.flash = bytes(flash)
        self.output_dir = self.temp / "backups"

    def run_backup(self, fake, **kwargs):
        return backup(openocd="fake-openocd", config=self.config,
                      bitstream=self.bitstream, output_dir=self.output_dir,
                      runner=fake, name="test.bin", **kwargs)

    def test_plan_only_does_not_create_or_run(self):
        fake = FakeOpenOcd(self.flash)
        self.assertIsNone(self.run_backup(fake, plan_only=True))
        self.assertEqual(fake.calls, [])
        self.assertFalse(self.output_dir.exists())

    def test_eight_segments_two_sessions_each_publish_exact_flash(self):
        fake = FakeOpenOcd(self.flash)
        output = self.run_backup(fake)
        self.assertEqual(output.read_bytes(), self.flash)
        self.assertEqual(len(fake.calls), 16)
        segments = self.output_dir / "test.bin.segments"
        self.assertEqual(len(list(segments.glob("*.bin"))), 16)
        self.assertEqual(len(list(segments.glob("*.openocd.log"))), 16)
        self.assertFalse((self.output_dir / "test.bin.partial").exists())

    def test_retry_keeps_failed_attempt_and_uses_clean_capture(self):
        fake = FakeOpenOcd(self.flash, {1: "error"})
        output = self.run_backup(fake)
        self.assertEqual(output.read_bytes(), self.flash)
        self.assertEqual(len(fake.calls), 17)
        log = (self.output_dir / "test.bin.segments" /
               "chunk00_pass1_attempt1.bin.openocd.log").read_text()
        self.assertIn("Error: failed read", log)

    def test_exhausted_timeout_never_publishes_backup(self):
        fake = FakeOpenOcd(self.flash, {1: "timeout", 2: "timeout"})
        with self.assertRaisesRegex(BackupError, "no complete backup"):
            self.run_backup(fake)
        self.assertFalse((self.output_dir / "test.bin").exists())
        self.assertEqual(len(fake.calls), 2)

    def test_short_read_never_publishes_backup(self):
        fake = FakeOpenOcd(self.flash, {1: "short", 2: "short"})
        with self.assertRaisesRegex(BackupError, "no complete backup"):
            self.run_backup(fake)
        self.assertFalse((self.output_dir / "test.bin").exists())

    def test_independent_read_mismatch_never_publishes_backup(self):
        fake = FakeOpenOcd(self.flash, {2: "mismatch"})
        with self.assertRaisesRegex(BackupError, "physical 0x00000"):
            self.run_backup(fake)
        self.assertFalse((self.output_dir / "test.bin").exists())

    def test_existing_output_is_not_overwritten(self):
        self.output_dir.mkdir()
        output = self.output_dir / "test.bin"
        output.write_bytes(b"KEEP")
        fake = FakeOpenOcd(self.flash)
        with self.assertRaisesRegex(BackupError, "already exists"):
            self.run_backup(fake)
        self.assertEqual(output.read_bytes(), b"KEEP")
        self.assertEqual(fake.calls, [])


if __name__ == "__main__":
    unittest.main()
