import struct
import tempfile
import unittest
import zlib
from pathlib import Path

from test_elf_to_hex import fixture
from uart_upload import BANNER, image_bytes, packet, transfer


class FakeSerial:
    def __init__(self, replies, banner=BANNER, output=b"", boot_extras=()):
        self.replies = bytearray(replies)
        self.banner = banner
        self.output = output
        self.boot_extras = list(boot_extras)
        self.sent = bytearray()
        self.read_until_count = 0

    def read_until(self, expected):
        self.read_until_count += 1
        if self.read_until_count == 1:
            return self.banner
        if self.sent:
            return self.output
        return self.boot_extras.pop(0) if self.boot_extras else b""

    def write(self, data):
        self.sent.extend(data)
        return len(data)

    def read(self, size):
        data = bytes(self.replies[:size])
        del self.replies[:size]
        return data


class UploadTests(unittest.TestCase):
    def test_padding_crc_and_limits(self):
        frame = packet(b"abc")
        self.assertEqual(struct.unpack("<4sIII", frame[:16]),
                         (b"RV32", 4, 0x80000000, zlib.crc32(b"abc\0")))
        self.assertEqual(frame[16:], b"abc\0")
        self.assertEqual(len(packet(bytes(896))), 912)
        for data in (b"", bytes(897)):
            with self.assertRaises(ValueError):
                packet(data)

    def test_elf_input_zero_fills_bss_and_checks_image_limit(self):
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / "test.elf"
            image.write_bytes(fixture())
            self.assertEqual(image_bytes(image), b"\x13" + bytes(11))
            self.assertEqual(packet(image_bytes(image))[16:],
                             b"\x13" + bytes(11))
            image.write_bytes(fixture(segments=[
                (0x80000000, b"\x13\x00\x00\x00", 900, 5)]))
            with self.assertRaises(ValueError):
                packet(image_bytes(image))

    def test_acknowledged_transfer(self):
        frame = packet(b"abc")
        serial = FakeSerial(b"A" * 16 + b"H" + b"A" * 4 + b"G")
        transfer(serial, frame)
        self.assertEqual(bytes(serial.sent), frame)

    def test_repeated_complete_banner_is_synchronized(self):
        frame = packet(b"abc")
        replies = b"A" * 16 + b"H" + b"A" * 4 + b"G"
        serial = FakeSerial(replies, boot_extras=[BANNER])
        transfer(serial, frame)
        self.assertEqual(bytes(serial.sent), frame)

    def test_partial_second_banner_stops_before_transmission(self):
        serial = FakeSerial(b"", boot_extras=[b"B"])
        with self.assertRaisesRegex(RuntimeError, "Unexpected data"):
            transfer(serial, packet(b"abc"))
        self.assertEqual(serial.sent, b"")

    def test_application_output_is_required(self):
        frame = packet(b"abc")
        replies = b"A" * 16 + b"H" + b"A" * 4 + b"G"
        transfer(FakeSerial(replies, output=b"APP A: UART loaded C!"), frame,
                 b"APP A: UART loaded C!")
        with self.assertRaises(RuntimeError):
            transfer(FakeSerial(replies, output=b""), frame,
                     b"APP A: UART loaded C!")

    def test_no_banner_no_write(self):
        serial = FakeSerial(b"", banner=b"Hello from C!\r\n")
        with self.assertRaises(RuntimeError):
            transfer(serial, packet(b"abc"))
        self.assertEqual(serial.sent, b"")

    def test_rejection_and_timeout_stop_transfer(self):
        for replies in (b"", b"E", b"A" * 16 + b"E",
                        b"A" * 16 + b"H" + b"A" * 4 + b"E"):
            serial = FakeSerial(replies)
            with self.assertRaises(RuntimeError):
                transfer(serial, packet(b"abc"))

    def test_bad_ack_reports_following_bytes(self):
        serial = FakeSerial(b"BOOT UART\r\n")
        with self.assertRaisesRegex(RuntimeError, "following bytes b'OOT UART"):
            transfer(serial, packet(b"abc"))


if __name__ == "__main__":
    unittest.main()
