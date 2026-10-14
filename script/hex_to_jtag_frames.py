import argparse
from pathlib import Path


CTRL_ADDR = 0xFFFF_FFFC
RAM_BASE = 0x8000_0000


def frame_bits(write, sel, addr, data):
    value = ((data & 0xFFFFFFFF) << 37) | ((addr & 0xFFFFFFFF) << 5)
    value |= ((sel & 0xF) << 1) | (1 if write else 0)
    return "".join("1" if (value >> i) & 1 else "0" for i in range(69))


def emit_command(lines, write, sel, addr, data, comment):
    lines.append(f"# {comment}")
    lines.append(f"SHIFT {frame_bits(write, sel, addr, data)}")
    lines.append("COMMIT")


def main():
    parser = argparse.ArgumentParser(
        description="Convert 32-bit little-endian hex firmware words into JTAG loader frames."
    )
    parser.add_argument("hex", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--base", type=lambda x: int(x, 0), default=RAM_BASE)
    args = parser.parse_args()

    words = []
    for line_no, raw in enumerate(args.hex.read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        words.append((line_no, int(line, 16) & 0xFFFFFFFF))

    lines = [
        "# JTAG loader text format for jtag_wb_loader.v",
        "# SHIFT carries 69 TDI bits LSB-first in SHIFT-DR; COMMIT means UPDATE-DR.",
        "",
    ]

    emit_command(lines, True, 0xF, CTRL_ADDR, 0x00000002, "hold CPU reset")
    for index, (_line_no, word) in enumerate(words):
        addr = args.base + index * 4
        emit_command(lines, True, 0xF, addr, word, f"write {addr:#010x} = {word:#010x}")
    emit_command(lines, True, 0xF, CTRL_ADDR, 0x00000003, "select RAM reset vector while CPU remains reset")
    emit_command(lines, True, 0xF, CTRL_ADDR, 0x00000001, "release CPU reset and boot from RAM")

    args.out.write_text("\n".join(lines) + "\n")
    print(f"wrote {len(words)} firmware words to {args.out}")


if __name__ == "__main__":
    main()
