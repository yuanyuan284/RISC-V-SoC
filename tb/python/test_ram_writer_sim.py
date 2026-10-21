import unittest

from prepare_ram_writer_sim import to_word_hex


class RamWriterImageTests(unittest.TestCase):
    def test_little_endian_words_and_full_bank_padding(self):
        lines = to_word_hex(bytes([0x13, 0x00, 0x00, 0x00, 0xaa])).splitlines()
        self.assertEqual(len(lines), 8192)
        self.assertEqual(lines[:3], ['00000013', '000000aa', '00000000'])
        self.assertEqual(lines[-1], '00000000')

    def test_rejects_empty_or_oversized_program(self):
        for image in (b'', bytes(32769)):
            with self.assertRaises(ValueError):
                to_word_hex(image)


if __name__ == '__main__':
    unittest.main()
