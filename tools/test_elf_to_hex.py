import struct
import unittest

from elf_to_hex import BASE, HEADER, PROGRAM_HEADER, load_elf
from elf_to_svf import svf_from_elf
from hex_to_svf import CTRL, MAGIC, command


def fixture(segments=None, entry=BASE, flags=0):
    if segments is None:
        segments = [(BASE, b"\x13\x00\x00\x00", 12, 5)]
    offset = HEADER.size + len(segments) * PROGRAM_HEADER.size
    headers, payload = [], bytearray()
    for address, contents, size, permissions in segments:
        headers.append(PROGRAM_HEADER.pack(
            1, offset + len(payload), address, address,
            len(contents), size, permissions, 1))
        payload.extend(contents)
    ident = b"\x7fELF\x01\x01\x01" + bytes(9)
    return HEADER.pack(ident, 2, 243, 1, entry, HEADER.size, 0, flags,
                       HEADER.size, PROGRAM_HEADER.size, len(segments), 0, 0, 0
                       ) + b"".join(headers) + payload


class ElfTests(unittest.TestCase):
    def test_stage2_svf_orders_guard_verify_and_boot(self):
        svf, count = svf_from_elf(fixture(), 0xF0)
        self.assertEqual(count, 3)
        self.assertLess(svf.index(f"TDO ({MAGIC:018X})"),
                        svf.index(f"TDI ({command(True, CTRL, 2):018X})"))
        self.assertLess(svf.index("// Verify 80000008"),
                        svf.index(f"TDI ({command(True, CTRL, 1):018X})"))

    def test_stage2_svf_preserves_stack_space(self):
        accepted = fixture([(BASE, bytes(4), 896, 5)])
        rejected = fixture([(BASE, bytes(4), 897, 5)])
        self.assertEqual(svf_from_elf(accepted, 0xF0)[1], 224)
        with self.assertRaisesRegex(ValueError, "896 bytes"):
            svf_from_elf(rejected, 0xF0)

    def test_bss_zero_fill(self):
        self.assertEqual(load_elf(fixture()), [0x13, 0, 0])

    def test_multiple_segments_gaps_and_partial_word(self):
        self.assertEqual(load_elf(fixture([
            (BASE, b"\x13\x00\x00\x00", 4, 5),
            (BASE + 12, b"\xaa", 2, 6)])), [0x13, 0, 0, 0xaa])

    def test_exact_ram_limit(self):
        self.assertEqual(len(load_elf(fixture([(BASE, bytes(4), 1024, 5)]))), 256)

    def test_bad_segments(self):
        for segments in ([ (BASE, bytes(4), 1025, 5) ],
                         [ (BASE - 4, bytes(8), 8, 5) ],
                         [ (BASE, bytes(4), 3, 5) ],
                         [ (BASE, bytes(8), 8, 5), (BASE + 4, bytes(4), 4, 6) ]):
            with self.subTest(segments=segments), self.assertRaises(ValueError):
                load_elf(fixture(segments))

    def test_entry_and_abi(self):
        for data in (fixture(entry=BASE + 4), fixture(flags=1),
                     fixture([(BASE, bytes(4), 4, 6)])):
            with self.assertRaises(ValueError):
                load_elf(data)

    def test_truncation(self):
        data = fixture()
        for cut in range(len(data)):
            with self.subTest(cut=cut), self.assertRaises(ValueError):
                load_elf(data[:cut])

    def test_wrong_format(self):
        for position, replacement in ((0, 0), (4, 2), (5, 2), (18, 0)):
            data = bytearray(fixture())
            data[position] = replacement
            with self.assertRaises(ValueError):
                load_elf(data)


if __name__ == "__main__":
    unittest.main()
