"""Read live unified XIP symbols via GDB and ensure the RTOS resumes."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import time

from validate_debug_sim import LoggedProcess, shutdown_openocd
from validate_unified_rtos_hardware import observe_heartbeats

ROOT = Path(__file__).resolve().parents[1]
BOARD = ROOT / 'script/openocd/board-iotelic-ft2232h.cfg'
GDB_SCRIPT = ROOT / 'script/gdb/inspect-unified-live.gdb'
ELF = ROOT / 'build/unified/freertos_xip.elf'


def openocd_tcl(command):
    with socket.create_connection(('127.0.0.1', 6666), timeout=3) as client:
        client.settimeout(3)
        client.sendall(command.encode('ascii') + b'\x1a')
        response = bytearray()
        while b'\x1a' not in response:
            chunk = client.recv(4096)
            if not chunk:
                raise RuntimeError(f'OpenOCD closed before replying to {command}')
            response.extend(chunk)
    return bytes(response).split(b'\x1a', 1)[0].decode('utf-8', errors='replace')


def check_ports_free():
    for port in (3333, 6666, 4444):
        with socket.socket() as probe:
            try:
                probe.bind(('127.0.0.1', port))
            except OSError as error:
                raise RuntimeError(f'Local OpenOCD port {port} is occupied') from error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--openocd', default=os.environ.get('OPENOCD', 'openocd'))
    parser.add_argument('--gdb', default=os.environ.get('RISCV_GDB', 'riscv-none-elf-gdb'))
    parser.add_argument('--port', default='COM3')
    parser.add_argument('--timeout', type=int, default=60)
    parser.add_argument('--plan-only', action='store_true')
    args = parser.parse_args()
    openocd_command = [args.openocd, '-f', str(BOARD)]
    gdb_command = [args.gdb, '-nx', '-batch', '-x', str(GDB_SCRIPT), str(ELF)]
    if args.plan_only:
        print(json.dumps({'mode': 'plan_only', 'openocd': openocd_command,
                          'gdb': gdb_command, 'would_write_ram_or_flash': False}, indent=2))
        return
    if not ELF.is_file():
        raise FileNotFoundError(f'Build unified firmware first: {ELF}')
    check_ports_free()

    output = ROOT / 'build/unified/hardware' / datetime.now().strftime('gdb_%Y%m%d-%H%M%S-%f')
    output.mkdir(parents=True, exist_ok=False)
    report = {'mode': 'hardware_unified_gdb_read_only', 'status': 'running',
              'elf_sha256': hashlib.sha256(ELF.read_bytes()).hexdigest(),
              'port': args.port, 'cpu_resume_confirmed_by_uart': False}
    ocd = None
    failure = None
    captured = bytearray()
    try:
        ocd = LoggedProcess(openocd_command, output / 'openocd.log', 'Listening on port 3333')
        ocd.wait_ready(timeout=args.timeout)
        result = subprocess.run(gdb_command, cwd=ROOT, capture_output=True,
                                text=True, encoding='utf-8', errors='replace',
                                timeout=args.timeout, check=False)
        gdb_log = result.stdout + result.stderr
        (output / 'gdb.log').write_text(gdb_log, encoding='utf-8')
        if (result.returncode or not re.search(r'Line \d+ of', gdb_log) or
                not re.search(r'\$\d+ = \d+', gdb_log) or 'detached' not in gdb_log):
            raise RuntimeError(f'GDB source/variable read failed (exit {result.returncode})')
        report['gdb_source_and_variable_read'] = True
    except BaseException as error:
        failure = error
    finally:
        if ocd:
            try:
                report['resume_reply'] = openocd_tcl('resume')
            except Exception as error:
                report['resume_error'] = str(error)
                if failure is None:
                    failure = error
            if ocd.proc.poll() is None:
                shutdown_openocd()
            ocd.stop()

    if failure is None:
        try:
            import serial

            port = serial.Serial(port=None, baudrate=115200, timeout=1)
            port.dtr = False
            port.rts = False
            port.port = args.port
            port.open()
            with port:
                port.reset_input_buffer()
                report['alive_samples'] = observe_heartbeats(
                    port, time.monotonic() + 15, captured)
            report['cpu_resume_confirmed_by_uart'] = True
        except BaseException as error:
            failure = error
    (output / 'uart.log').write_bytes(captured)
    report['status'] = 'passed' if failure is None else 'failed'
    if failure is not None:
        report['error'] = str(failure)
    report['ended_utc'] = datetime.now(timezone.utc).isoformat()
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(f'UNIFIED_GDB_REPORT: {output / "report.json"}', flush=True)
    if failure is not None:
        raise failure
    print('UNIFIED_GDB_LIVE_PASS', flush=True)


if __name__ == '__main__':
    main()
