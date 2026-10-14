import tempfile
import unittest
from pathlib import Path

from hex_to_svf import BASE, CTRL, MAGIC, command, generate, load_words


class SvfTests(unittest.TestCase):
    def test_command_wire_contract(self):
        frame = command(True, BASE + 4, 0x12345678)
        self.assertEqual(frame & 31, 31)
        self.assertEqual((frame >> 5) & 0xFFFFFFFF, BASE + 4)
        self.assertEqual(frame >> 37, 0x12345678)

    def test_guard_and_verify_before_boot(self):
        text = generate([0x12345678, 0xFFFFFFFF], 0xF0)
        guard = text.index(f"TDO ({MAGIC:018X})")
        hold = text.index(f"TDI ({command(True, CTRL, 2):018X})")
        verify = text.index("// Verify 80000004")
        arm = text.index(f"TDI ({command(True, CTRL, 3):018X})")
        boot = text.index(f"TDI ({command(True, CTRL, 1):018X})")
        self.assertLess(guard, hold)
        self.assertLess(hold, verify)
        self.assertLess(verify, arm)
        self.assertLess(arm, boot)
        self.assertTrue(text.endswith("SIR 8 TDI (FF);\nRUNTEST 32 TCK;\n"))

    def test_probe_has_no_control_or_ram_commands(self):
        text = generate([1], 0xF0, probe=True)
        self.assertEqual(text.count("SDR 69"), 1)
        self.assertIn("SDR 69 TDI (000000000000000000)", text)

    def test_invalid_firmware_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "image.hex"
            for content in ("", "100000000", "@0000", "12345678\n" * 257):
                path.write_text(content)
                with self.subTest(content=content[:20]), self.assertRaises(ValueError):
                    load_words(path)
            path.write_text("0d800313 // baud\n# comment\n0000006f\n")
            self.assertEqual(load_words(path), [0x0D800313, 0x6F])


if __name__ == "__main__":
    unittest.main()
