import struct
import unittest
import zlib

from test_uart_upload import FakeSerial
from prepare_stage3_test_frames import build_cases
from uart_upload import transfer
from uart_upload_stage3 import BANNER, MAX_IMAGE, packet


class Stage3Tests(unittest.TestCase):
    def test_boundary_frames_are_exact(self):
        cases = build_cases(b"CODE")
        self.assertEqual(cases["min_image"], packet(b"\x6f\x00\x00\x00"))
        self.assertEqual(len(cases["min_image"]), 20)
        self.assertEqual(len(cases["max_image"]), MAX_IMAGE + 16)
        self.assertEqual(cases["max_header"], cases["max_image"][:16])
        self.assertEqual(cases["max_image"][16:20], b"CODE")
        self.assertEqual(cases["max_image"][-4:], b"EDGE")
        self.assertEqual(struct.unpack("<4sIII", cases["max_image"][:16]),
                         (b"RV32", MAX_IMAGE, 0x80000000,
                          zlib.crc32(cases["max_image"][16:])))
        for name, expected in (("zero", (b"RV32", 0, 0x80000000)),
                               ("oversize", (b"RV32", MAX_IMAGE + 4, 0x80000000)),
                               ("unaligned", (b"RV32", MAX_IMAGE - 1, 0x80000000)),
                               ("wrong_entry", (b"RV32", 4, 0x80000004)),
                               ("wrong_magic", (b"BAD!", 4, 0x80000000))):
            self.assertEqual(struct.unpack("<4sII", cases[name][:12]), expected)

    def test_capacity_alignment_and_crc(self):
        for size in (1, 2, 3, 4, 897, 32769, MAX_IMAGE - 4,
                     MAX_IMAGE - 3, MAX_IMAGE - 2, MAX_IMAGE - 1, MAX_IMAGE):
            data = bytes((i % 251 for i in range(size)))
            frame = packet(data)
            padded = data + bytes((-size) % 4)
            self.assertEqual(frame[16:], padded)
            self.assertEqual(struct.unpack("<4sIII", frame[:16]),
                             (b"RV32", len(padded), 0x80000000, zlib.crc32(padded)))
        for size in (0, MAX_IMAGE + 1, MAX_IMAGE + 4, 65536):
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

    def test_maximum_transfer_sends_last_byte(self):
        frame = packet(bytes((i % 251 for i in range(MAX_IMAGE))))
        replies = b"A" * 16 + b"H" + b"A" * MAX_IMAGE + b"G"
        serial = FakeSerial(replies, banner=BANNER, output=b"APP A: UART loaded C!")
        progress = []
        transfer(serial, frame, b"APP A: UART loaded C!", banner=BANNER,
                 progress=lambda done, total: progress.append((done, total)))
        self.assertEqual(serial.sent, frame)
        self.assertEqual(progress[-1], (MAX_IMAGE, MAX_IMAGE))

    def test_crc_rejection_and_missing_output_are_failures(self):
        frame = packet(bytes(4))
        replies = b"A" * 16 + b"H" + b"A" * 4
        for suffix, output in ((b"E", b""), (b"G", b"STAGE3 FAIL")):
            with self.assertRaises(RuntimeError):
                transfer(FakeSerial(replies + suffix, banner=BANNER, output=output),
                         frame, b"STAGE3 PASS", banner=BANNER)


if __name__ == "__main__":
    unittest.main()
