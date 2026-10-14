"""Experimental stage-2 BootROM BIN uploader; not for the stage-1 bitstream."""

import argparse
from pathlib import Path
import struct
import zlib
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'build/deps/pyserial'))

from elf_to_hex import load_elf

BASE = 0x80000000
MAX_IMAGE = 896
BANNER = b"BOOT UART\r\n"


def packet(binary):
    if not binary or len(binary) > MAX_IMAGE:
        raise ValueError("BIN must contain 1..896 bytes (128 bytes reserved for stack)")
    binary += bytes((-len(binary)) % 4)
    return struct.pack("<4sIII", b"RV32", len(binary), BASE,
                       zlib.crc32(binary)) + binary


def image_bytes(path):
    data = path.read_bytes()
    if path.suffix.lower() == ".elf":
        words = load_elf(data)
        data = struct.pack(f"<{len(words)}I", *words)
    elif path.suffix.lower() != ".bin":
        raise ValueError("Expected a .elf or .bin image")
    return data


def expect(serial, wanted):
    got = serial.read(len(wanted))
    if got != wanted:
        old_timeout = serial.timeout
        serial.timeout = 0.2
        following = serial.read(32)
        serial.timeout = old_timeout
        raise RuntimeError(f"Expected {wanted!r}, received {got!r}; "
                           f"following bytes {following!r}; reset board before retry")


def transfer(serial, frame, expected_output=b"", *, banner=BANNER, progress=None):
    # Wait for a fresh reset banner; never silently transmit into an application.
    received = serial.read_until(banner)
    if not received.endswith(banner):
        raise RuntimeError(f"No BootROM banner; received {received!r}; "
                           f"hardware/reset producing {banner!r} is required")
    # A bouncing reset can print another complete banner before the first
    # header byte. Wait briefly for the last banner, but never ignore noise.
    serial.timeout = 0.25
    for _ in range(4):
        extra = serial.read_until(banner)
        if not extra:
            break
        if extra != banner:
            raise RuntimeError(f"Unexpected data after BootROM banner: {extra!r}")
    else:
        raise RuntimeError("BootROM banner repeats; check FPGA reset button")
    serial.timeout = 15
    for byte in frame[:16]:
        if serial.write(bytes([byte])) != 1:
            raise RuntimeError("Short serial write")
        expect(serial, b"A")
    expect(serial, b"H")
    for index, byte in enumerate(frame[16:], 1):
        if serial.write(bytes([byte])) != 1:
            raise RuntimeError("Short serial write")
        expect(serial, b"A")
        if progress and (index % 1024 == 0 or index == len(frame) - 16):
            progress(index, len(frame) - 16)
    expect(serial, b"G")
    if expected_output:
        output = serial.read_until(expected_output)
        if not output.endswith(expected_output):
            raise RuntimeError(f"Application output mismatch: received {output!r}")
        print(f"Application output: {output!r}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path, help="RV32IM ELF or flat RAM BIN")
    parser.add_argument("--port", required=True)
    parser.add_argument("--boot-timeout", type=float, default=60,
                        help="seconds to wait for the next FPGA reset banner")
    parser.add_argument("--expect-text", default="",
                        help="ASCII text that the application must print after launch")
    args = parser.parse_args()
    try:
        frame = packet(image_bytes(args.image))
        import serial
        # Explicit line states avoid asserting reset on adapters wired to RTS/DTR.
        port = serial.Serial(port=None, baudrate=115200,
                             timeout=args.boot_timeout,
                             write_timeout=3)
        port.dtr = False
        port.rts = False
        port.port = args.port
        port.open()
        # Discard a banner left in the adapter buffer. The next FPGA reset
        # must produce the banner that authorizes this transfer.
        port.reset_input_buffer()
        with port:
            print("Waiting for BOOT UART: press FPGA reset, not downloader reset.")
            transfer(port, frame, args.expect_text.encode("ascii"))
    except (OSError, ValueError, RuntimeError, ImportError) as exc:
        parser.exit(1, f"Upload failed: {exc}\n")
    print("BootROM accepted CRC and acknowledged application launch.")


if __name__ == "__main__":
    main()
