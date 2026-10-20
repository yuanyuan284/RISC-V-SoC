"""Read the simulated Flash through real OpenOCD/JTAG and compare XIP bytes."""
import argparse
from pathlib import Path
import socket
import sys

from validate_debug_sim import LoggedProcess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/flash'


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--openocd', required=True)
    parser.add_argument('--vvp', required=True)
    parser.add_argument('--timeout', type=int, default=600)
    args = parser.parse_args()
    image = (BUILD / 'hello.xip').read_bytes()
    if len(image) < 32:
        raise ValueError('The XIP image must contain at least 32 bytes')
    for port in (9824, 3333, 6666, 4444):
        with socket.socket() as probe:
            try:
                probe.bind(('127.0.0.1', port))
            except OSError:
                parser.error(f'Port {port} is already occupied')
    dump = BUILD / 'jtag-image-head.bin'
    dump.unlink(missing_ok=True)
    tcl_path = dump.as_posix()
    bridge = ocd = None
    try:
        bridge = LoggedProcess(
            [sys.executable, str(ROOT / 'script/debug_remote_sim.py'),
             '--vvp', args.vvp, '--image', str(BUILD / 'flash-remote.vvp'),
             '--cwd', str(BUILD), '--image-bytes', str(len(image))],
            BUILD / 'flash_jtag_bridge.log', 'JTAG simulator listening')
        bridge.wait_ready(timeout=120)
        ocd = LoggedProcess(
            [args.openocd, '-f', 'script/openocd/simulation.cfg', '-c',
             f'init; halt; dump_image {{{tcl_path}}} 0x30050000 32; shutdown'],
            BUILD / 'flash_jtag_openocd.log')
        ocd.wait(args.timeout)
        bridge.wait(15)
        if dump.read_bytes() != image[:32]:
            raise RuntimeError('OpenOCD Flash readback differs from the XIP image')
        print('PASS OpenOCD/JTAG Flash-window readback matches XIP image', flush=True)
    finally:
        if ocd:
            ocd.stop()
        if bridge:
            bridge.stop()


if __name__ == '__main__':
    main()
