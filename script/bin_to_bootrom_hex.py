"""Generate the complete 1 KiB stage-2 ROM image from cross-compiled BIN."""
import argparse
from pathlib import Path
import struct

def convert(data):
    if not data or len(data) > 1024:
        raise ValueError("BootROM must contain 1..1024 bytes")
    data += bytes(1024 - len(data))
    return "".join(f"{word:08x}\n" for (word,) in struct.iter_unpack("<I", data))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bin", type=Path)
    parser.add_argument("hex", type=Path)
    args = parser.parse_args()
    try:
        result = convert(args.bin.read_bytes())
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    args.hex.write_text(result, encoding="ascii")
