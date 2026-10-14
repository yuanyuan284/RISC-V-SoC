"""Upload an objcopy BIN to the 8 KiB BootROM / 64 KiB RAM Stage-3 SoC."""
import argparse
from pathlib import Path
import struct
import sys
import zlib

from uart_upload import transfer

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "build/deps/pyserial"))

BASE = 0x80000000
MAX_IMAGE = 61440
BANNER = b"BOOT UART 64K\r\n"


def packet(binary):
    binary += bytes((-len(binary)) % 4)
    if not 0 < len(binary) <= MAX_IMAGE:
        raise ValueError("Aligned BIN must contain 1..61440 bytes; 4 KiB reserved for stack")
    return struct.pack("<4sIII", b"RV32", len(binary), BASE,
                       zlib.crc32(binary)) + binary


def image_bytes(path):
    if path.suffix.lower() != ".bin":
        raise ValueError("Stage-3 downloads objcopy .bin files; ELF/Intel HEX are build artifacts")
    return path.read_bytes()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--port", required=True)
    parser.add_argument("--boot-timeout", type=float, default=60)
    parser.add_argument("--expect-text", default="STAGE3 PASS")
    args = parser.parse_args()
    try:
        frame = packet(image_bytes(args.image))
        import serial
        port = serial.Serial(port=None, baudrate=115200,
                             timeout=args.boot_timeout, write_timeout=3)
        port.dtr = False
        port.rts = False
        port.port = args.port
        port.open()
        with port:
            port.reset_input_buffer()
            print("Listening for BOOT UART 64K; press and release FPGA SW2.", flush=True)
            transfer(port, frame, args.expect_text.encode("ascii"), banner=BANNER,
                     progress=lambda done, total: print(f"Uploaded {done}/{total} bytes", flush=True))
    except (OSError, ValueError, RuntimeError, ImportError) as exc:
        parser.exit(1, f"Upload failed: {exc}\n")
    print("BootROM accepted CRC and application output was verified." if args.expect_text
          else "BootROM accepted CRC and acknowledged launch; application output unchecked.")


if __name__ == "__main__":
    main()
