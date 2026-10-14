"""Check BootROM rejection/recovery on a real UART, then run a supplied BIN."""
import argparse
from pathlib import Path
import struct

from uart_upload import expect, transfer
from uart_upload_stage3 import BASE, BANNER, MAX_IMAGE, image_bytes, packet


def send_acknowledged(port, data):
    for byte in data:
        if port.write(bytes([byte])) != 1:
            raise RuntimeError("Short serial write")
        expect(port, b"A")


def rejection_tests(port):
    expect(port, BANNER)
    port.timeout = 15
    cases = [
        ("zero length", b"RV32", 0, BASE),
        ("oversized image", b"RV32", MAX_IMAGE + 4, BASE),
        ("unaligned length", b"RV32", 3, BASE),
        ("wrong entry", b"RV32", 4, BASE + 4),
        ("wrong magic", b"BAD!", 4, BASE),
    ]
    for label, magic, length, entry in cases:
        send_acknowledged(port, struct.pack("<4sIII", magic, length, entry, 0))
        expect(port, b"E")
        expect(port, BANNER)
        print(f"PASS: {label} rejected; BootROM recovered", flush=True)
    send_acknowledged(port, struct.pack("<4sIII", b"RV32", 4, BASE, 0))
    expect(port, b"H")
    send_acknowledged(port, bytes(4))
    expect(port, b"E")
    # Leave the fresh banner queued for the normal uploader's synchronization.
    print("PASS: corrupted CRC rejected", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--port", required=True)
    parser.add_argument("--boot-timeout", type=float, default=180)
    parser.add_argument("--expect-text", required=True)
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
            print("Listening for fresh Stage-3 BootROM banner", flush=True)
            rejection_tests(port)
            transfer(port, frame, args.expect_text.encode("ascii"), banner=BANNER)
            print("PASS: valid BIN executed after all six rejected frames", flush=True)
    except (OSError, ValueError, RuntimeError, ImportError) as exc:
        parser.exit(1, f"Hardware validation failed: {exc}\n")


if __name__ == "__main__":
    main()
