import struct
import unittest
import zlib

from test_uart_upload import FakeSerial
from uart_upload import transfer
from uart_upload_stage3 import BANNER, MAX_IMAGE, packet


class Stage3Tests(unittest.TestCase):
    def test_capacity_alignment_and_crc(self):
        for size in (1, 897, 32769, MAX_IMAGE - 1, MAX_IMAGE):
            data = bytes((i % 251 for i in range(size)))
            frame = packet(data)
            padded = data + bytes((-size) % 4)
            self.assertEqual(frame[16:], padded)
            self.assertEqual(struct.unpack("<4sIII", frame[:16]),
                             (b"RV32", len(padded), 0x80000000, zlib.crc32(padded)))
        for size in (0, MAX_IMAGE + 1, 65536):
            with self.assertRaises(ValueError):
                packet(bytes(size))

    def test_old_hardware_is_rejected_before_any_write(self):
        serial = FakeSerial(b"")
        with self.assertRaisesRegex(RuntimeError, "No BootROM banner"):
            transfer(serial, packet(bytes(1024)), banner=BANNER)
        self.assertEqual(serial.sent, b"")

    def test_large_transfer_and_formatted_output(self):
        frame = packet(bytes(42424))
        replies = b"A" * 16 + b"H" + b"A" * (len(frame) - 16) + b"G"
        serial = FakeSerial(replies, banner=BANNER,
                            output=b"FLOAT=3.25\r\nSTAGE3 PASS")
        progress = []
        transfer(serial, frame, b"STAGE3 PASS", banner=BANNER,
                 progress=lambda done, total: progress.append((done, total)))
        self.assertEqual(serial.sent, frame)
        self.assertEqual(progress[-1], (42424, 42424))

    def test_crc_rejection_and_missing_output_are_failures(self):
        frame = packet(bytes(4))
        replies = b"A" * 16 + b"H" + b"A" * 4
        for suffix, output in ((b"E", b""), (b"G", b"STAGE3 FAIL")):
            with self.assertRaises(RuntimeError):
                transfer(FakeSerial(replies + suffix, banner=BANNER, output=output),
                         frame, b"STAGE3 PASS", banner=BANNER)


if __name__ == "__main__":
    unittest.main()
