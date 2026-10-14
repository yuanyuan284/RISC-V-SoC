"""Build a small UART image using only the stage-1 core's supported RV32I ops."""

import argparse
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("out", type=Path)
    parser.add_argument("--message", default="Hello from JTAG!")
    args = parser.parse_args()
    try:
        message = (args.message + "\r\n").encode("ascii")
    except UnicodeEncodeError:
        parser.error("The UART message must be ASCII")
    # LUI x5, UART base; ADDI x6, x0, 216; SW x6, 0(x5).
    words = [0x400012B7, 0x0D800313, 0x0062A023]
    for byte in message:
        words += [(byte << 20) | 0x313, 0x0462A623]
    words += [0x0000006F]
    if len(words) > 256:
        parser.error("Message exceeds the 1 KiB instruction RAM")
    args.out.write_text("".join(f"{word:08x}\n" for word in words), encoding="ascii")
    print(f"Wrote {len(words)} words to {args.out}")


if __name__ == "__main__":
    main()
