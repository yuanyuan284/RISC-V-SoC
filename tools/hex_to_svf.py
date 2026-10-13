"""Generate EF2 loader SVF; probe the selected user IR before any RAM write."""

import argparse
from pathlib import Path

MAGIC = 0x4A544147 << 37
CTRL = 0xFFFF_FFFC
BASE = 0x8000_0000
LIMIT = BASE + 1024


def command(write, address, data=0):
    return (data << 37) | (address << 5) | 0x1E | int(write)


def scan(tdi=0, expected=None, mask=None):
    line = f"SDR 69 TDI ({tdi:018X})"
    if expected is not None:
        line += f" TDO ({expected:018X}) MASK ({mask:018X})"
    return line + ";"


def preamble(user_ir):
    return [
        "// EF2 stage-1 loader; use only after configuring its matching bitstream.",
        "TRST OFF;", "ENDIR IDLE;", "ENDDR IDLE;",
        "HIR 0;", "HDR 0;", "TIR 0;", "TDR 0;",
        "FREQUENCY 1E6 HZ;", "STATE RESET;", "STATE IDLE;",
        "RUNTEST 32 TCK;", "SIR 8 TDI (06);",
        "SDR 32 TDI (00000000) TDO (03004C37) MASK (FFFFFFFF);",
        f"SIR 8 TDI ({user_ir:02X});", "RUNTEST 32 TCK;",
        scan(expected=MAGIC, mask=0xFFFFFFFF << 37),
        "RUNTEST 32 TCK;",
    ]


def transact(lines, write, address, data=0, expected_data=None):
    lines += [scan(command(write, address, data)), "RUNTEST 64 TCK;"]
    # Completion is valid, idle, and free of bus errors. Bit 35 is a toggle.
    expected = MAGIC | (1 << 34)
    mask = (0xFFFFFFFF << 37) | (7 << 32)
    if expected_data is not None:
        expected |= expected_data
        mask |= 0xFFFFFFFF
    lines += [scan(expected=expected, mask=mask), "RUNTEST 32 TCK;"]


def load_words(path):
    words = []
    for line_no, raw in enumerate(path.read_text(encoding="ascii").splitlines(), 1):
        value = raw.split("//", 1)[0].split("#", 1)[0].strip()
        if not value:
            continue
        if len(value) > 8 or any(c not in "0123456789abcdefABCDEF" for c in value):
            raise ValueError(f"{path}:{line_no}: expected a 32-bit hex word")
        words.append(int(value, 16))
    if not words or len(words) * 4 > LIMIT - BASE:
        raise ValueError("Firmware must contain 1..256 words for the 1 KiB RAM")
    return words


def generate(words, user_ir, probe=False):
    if user_ir in (0x01, 0x06, 0x30, 0x39, 0x3B, 0x3D, 0xFF):
        raise ValueError("User IR collides with an EF2 configuration instruction")
    lines = preamble(user_ir)
    if not probe:
        transact(lines, True, CTRL, 2, expected_data=2)
        for index, word in enumerate(words):
            lines.append(f"// Write {BASE + index * 4:08X}")
            transact(lines, True, BASE + index * 4, word)
        for index, word in enumerate(words):
            lines.append(f"// Verify {BASE + index * 4:08X}")
            transact(lines, False, BASE + index * 4, expected_data=word)
        # Present the RAM reset vector while the CPU is still held in reset.
        transact(lines, True, CTRL, 3, expected_data=3)
        transact(lines, True, CTRL, 1, expected_data=1)
    # Leave the TAP idle so the host can download again without reconfiguration.
    lines += ["SIR 8 TDI (FF);", "RUNTEST 32 TCK;"]
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("hex", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--user-ir", type=lambda v: int(v, 0), required=True)
    parser.add_argument("--probe", action="store_true")
    args = parser.parse_args()
    try:
        if not 0 <= args.user_ir <= 255:
            raise ValueError("User IR must fit in 8 bits")
        words = load_words(args.hex)
        result = generate(words, args.user_ir, args.probe)
    except ValueError as exc:
        parser.error(str(exc))
    args.out.write_text(result, encoding="ascii")
    print(f"Wrote {args.out}; {len(words)} words; probe={args.probe}")


if __name__ == "__main__":
    main()
