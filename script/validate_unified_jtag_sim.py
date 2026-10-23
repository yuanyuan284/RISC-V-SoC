"""Validate the unified CPU JTAG TAP after its FreeRTOS XIP startup in RTL."""
import argparse
from pathlib import Path
import socket
import sys

from validate_debug_sim import LoggedProcess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/unified'
MARKER = 'PASS unified XIP FreeRTOS CPU JTAG halt, memory, step and hardware breakpoint'


def require_bootrom_startup(log):
    markers = ('SIM_FAST_BOOT_CRC prefix_bytes=64', 'BOOT FLASH', 'FREERTOS START',
               'PASS unified XIP FreeRTOS preemption, queue and interrupts')
    positions = [log.find(marker) for marker in markers]
    if any(position < 0 for position in positions) or positions != sorted(positions):
        raise RuntimeError('BootROM, FreeRTOS startup, and self-test markers missing or out of order')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--openocd', required=True)
    parser.add_argument('--vvp', required=True)
    parser.add_argument('--timeout', type=int, default=600)
    parser.add_argument('--bootrom', action='store_true',
                        help='Require Flash BootROM and FreeRTOS self-test before JTAG opens')
    args = parser.parse_args()
    image = BUILD / 'freertos_xip.xip'
    if not image.is_file():
        parser.error('Run build_unified_firmware.ps1 first')
    for port in (9824, 3333, 6666, 4444):
        with socket.socket() as probe:
            try:
                probe.bind(('127.0.0.1', port))
            except OSError:
                parser.error(f'Port {port} is already occupied')
    bridge = ocd = None
    try:
        bridge_command = [sys.executable, str(ROOT / 'script/debug_remote_sim.py'),
                          '--vvp', args.vvp, '--image', str(BUILD / 'unified_xip.vvp'),
                          '--cwd', str(BUILD), '--image-bytes', str(image.stat().st_size)]
        if args.bootrom:
            bridge_command.extend(('--fast-boot-crc', '--progress'))
        bridge_log = BUILD / 'unified_jtag_bridge.log'
        bridge = LoggedProcess(
            bridge_command,
            bridge_log, 'JTAG simulator listening',
            kill_tree=True)
        try:
            bridge.wait_ready(timeout=args.timeout)
        except (RuntimeError, TimeoutError) as error:
            tail = bridge_log.read_text(encoding='utf-8', errors='replace').splitlines()[-8:]
            raise type(error)(f'{error}; bridge output: {tail}') from error
        if args.bootrom:
            startup_log = bridge_log.read_text(encoding='utf-8')
            require_bootrom_startup(startup_log)
        ocd = LoggedProcess(
            [args.openocd, '-f', 'script/openocd/simulation.cfg',
             '-f', 'script/openocd/validate-unified.tcl'],
            BUILD / 'unified_jtag_openocd.log')
        ocd.wait(args.timeout)
        bridge.wait(15)
        log = (BUILD / 'unified_jtag_openocd.log').read_text(encoding='utf-8')
        if MARKER not in log or 'Error:' in log:
            raise RuntimeError('Unified JTAG validation marker missing or OpenOCD error')
        if args.bootrom:
            print('PASS unified Flash BootROM, FreeRTOS self-test, and CPU JTAG in one RTL run',
                  flush=True)
        print(MARKER, flush=True)
    finally:
        if ocd:
            ocd.stop()
        if bridge:
            bridge.stop()


if __name__ == '__main__':
    main()
