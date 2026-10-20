"""Run OpenOCD/GDB validation against RTL, or explicitly selected board hardware."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/debug'
ADAPTER_CONFIGS = {
    'jlink': 'script/openocd/board-jlink.cfg',
    'cmsis-dap': 'script/openocd/board-cmsis-dap.cfg',
    'iotelic-ft2232h': 'script/openocd/board-iotelic-ft2232h.cfg',
}
TEST_MARKERS = {
    'core': ('PASS independent RISC-V JTAG RAM, registers, single-step, reset and breakpoint',),
    'gdb': ('PASS GDB ELF load and C breakpoint', 'PASS GDB stepi',
            'PASS C result=9 data=7', 'PASS GDB software breakpoint', 'PASS GDB C source step'),
    'download': ('PASS full 65536-byte RAM JTAG transfer and verification',
                 'PASS Stage3 application ELF load and verification',
                 'PASS instruction cache coherency on code reload'),
}


def validate_log(test, log):
    if not all(marker in log for marker in TEST_MARKERS[test]):
        raise RuntimeError(f'{test} assertions did not all complete')
    if 'MIS-MATCHED' in log or 'FAIL ' in log:
        raise RuntimeError(f'{test} reported a failed assertion or image mismatch')


def openocd_command(args, test, output):
    config = ADAPTER_CONFIGS[args.adapter] if args.adapter else 'script/openocd/simulation.cfg'
    command = [args.openocd, '-f', config]
    if test == 'gdb':
        command += ['-c', 'init; halt']
    else:
        script = 'validate-debug.tcl' if test == 'core' else 'validate-download.tcl'
        # The output is our fixed build directory, not arbitrary Tcl input.
        command += ['-c', f'set validation_output {{{output.as_posix()}}}',
                    '-f', f'script/openocd/{script}']
    return command


def gdb_command(args):
    return [args.gdb, '-batch', '-x', 'script/gdb/validate-debug.gdb',
            'build/debug/debug_demo.elf']


def input_hashes(tests, adapter=None):
    paths = ['build/cpu-debug/VexRiscvDebug.v', 'rtl/stage3/stage3_debug_top.v',
             'script/openocd/riscv-debug.cfg']
    if adapter:
        paths += ['build/debug/stage3_debug.bit', 'constraints/debug.adc', 'constraints/debug.sdc',
                  ADAPTER_CONFIGS[adapter]]
        if adapter == 'iotelic-ft2232h':
            paths.append('script/openocd/iotelic-ft2232h.cfg')
    else:
        paths.append('build/debug/remote.vvp')
    if 'gdb' in tests:
        paths += ['build/debug/debug_demo.elf', 'script/gdb/validate-debug.gdb']
    if 'download' in tests:
        paths += ['build/stage3/app_a.elf', 'script/openocd/validate-download.tcl']
    if 'core' in tests:
        paths.append('script/openocd/validate-debug.tcl')
    return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in paths}


class LoggedProcess:
    def __init__(self, command, log, ready_text=None):
        self.ready = threading.Event()
        self.ready_text = ready_text
        self.proc = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, text=True,
                                     encoding='utf-8', errors='replace')
        self.thread = threading.Thread(target=self.capture, args=(log,), daemon=True)
        self.thread.start()

    def capture(self, log):
        with log.open('w', encoding='utf-8') as stream:
            for line in self.proc.stdout:
                stream.write(line)
                stream.flush()
                if self.ready_text and self.ready_text in line:
                    self.ready.set()
                if 'PASS ' in line or 'FAIL ' in line:
                    print(line.rstrip(), flush=True)

    def wait_ready(self, timeout=60):
        deadline = time.monotonic() + timeout
        while not self.ready.wait(0.1):
            if self.proc.poll() is not None:
                raise RuntimeError('Process exited before readiness; inspect build/debug logs')
            if time.monotonic() >= deadline:
                raise TimeoutError('Process readiness timed out')

    def wait(self, timeout):
        result = self.proc.wait(timeout=timeout)
        self.thread.join(timeout=5)
        if result:
            raise RuntimeError(f'Process exited with code {result}; inspect build/debug logs')

    def stop(self):
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(timeout=5)
        self.thread.join(timeout=5)


def shutdown_openocd():
    try:
        with socket.create_connection(('127.0.0.1', 6666), timeout=3) as client:
            client.sendall(b'shutdown\x1a')
    except OSError:
        pass


def run_test(args, test, output=BUILD):
    bridge = ocd = gdb = None
    print(f'Starting {test} validation', flush=True)
    if test == 'download':
        if not (ROOT / 'build/stage3/app_a.elf').is_file():
            raise FileNotFoundError('Build Stage3 firmware before the download test')
        pattern = bytes(((i * 37) ^ (i >> 8) ^ 0xa5) & 255 for i in range(65536))
        (output / 'ram-pattern.bin').write_bytes(pattern)
        (output / 'ram-readback.bin').unlink(missing_ok=True)
    try:
        if not args.adapter:
            bridge_command = [sys.executable, str(ROOT / 'script/debug_remote_sim.py'),
                              '--vvp', args.vvp]
            if args.wave:
                bridge_command.append('--wave')
            bridge = LoggedProcess(bridge_command, output / f'{test}_sim.log',
                                   'JTAG simulator listening')
            bridge.wait_ready()
        command = openocd_command(args, test, output)
        if test == 'gdb':
            ocd = LoggedProcess(command, output / 'openocd_gdb.log', 'Listening on port 3333')
            ocd.wait_ready()
            gdb = LoggedProcess(gdb_command(args), output / 'gdb_validation.log')
            gdb.wait(args.timeout)
            validate_log(test, (output / 'gdb_validation.log').read_text(encoding='utf-8'))
            shutdown_openocd()
        else:
            log_name = 'openocd_validation.log' if test == 'core' else 'download_validation.log'
            ocd = LoggedProcess(command, output / log_name)
        ocd.wait(args.timeout)
        if bridge:
            bridge.wait(15)
        if test != 'gdb':
            validate_log(test, (output / log_name).read_text(encoding='utf-8'))
        if test == 'download':
            if (output / 'ram-readback.bin').read_bytes() != pattern:
                raise RuntimeError('Full 65536-byte RAM readback differs')
            print('PASS full 65536-byte RAM readback byte comparison', flush=True)
        print(f'PASS {test} validation completed', flush=True)
    finally:
        if gdb:
            gdb.stop()
        if ocd:
            if ocd.proc.poll() is None:
                shutdown_openocd()
                try:
                    ocd.proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    pass
            ocd.stop()
        if bridge:
            bridge.stop()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--test', choices=('core', 'gdb', 'download', 'all'), default='all')
    parser.add_argument('--openocd', default=os.environ.get('OPENOCD', 'openocd'))
    parser.add_argument('--vvp', default=os.environ.get('VVP', 'vvp'))
    parser.add_argument('--gdb', default=os.environ.get('RISCV_GDB', 'riscv-none-elf-gdb'))
    parser.add_argument('--timeout', type=int, default=3600)
    parser.add_argument('--adapter', choices=tuple(ADAPTER_CONFIGS),
                        help='Select physical hardware instead of the RTL simulator')
    parser.add_argument('--confirm-ram-overwrite', action='store_true',
                        help='Acknowledge board CPU reset/halt and destructive RAM tests')
    parser.add_argument('--plan-only', action='store_true', help='Print commands; never start tools')
    parser.add_argument('--wave', action='store_true',
                        help='Capture selected RTL signals to debug_remote.vcd in simulation mode')
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    if args.adapter and not args.confirm_ram_overwrite and not args.plan_only:
        parser.error('Hardware tests overwrite RAM and reset/halt the CPU; add --confirm-ram-overwrite')
    if args.adapter and args.wave:
        parser.error('--wave captures RTL simulation only; omit --adapter')
    tests = ('core', 'gdb', 'download') if args.test == 'all' else (args.test,)
    output = BUILD if not args.adapter else BUILD / 'hardware' / datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    if args.plan_only:
        plan = {'mode': 'hardware' if args.adapter else 'simulation', 'adapter': args.adapter,
                'output': str(output), 'fpga_configuration': 'not performed',
                'would_overwrite_ram': True, 'commands': []}
        for test in tests:
            plan['commands'].append({'test': test, 'openocd': openocd_command(args, test, output)})
            if test == 'gdb':
                plan['commands'][-1]['gdb'] = gdb_command(args)
        print(json.dumps(plan, indent=2))
        return
    try:
        hashes = input_hashes(tests, args.adapter)
    except FileNotFoundError as error:
        parser.error(f'Missing input {error.filename}; build the selected CPU/firmware first')
    ports = (3333, 6666, 4444) if args.adapter else (9824, 3333, 6666, 4444)
    for port in ports:
        with socket.socket() as probe:
            try:
                probe.bind(('127.0.0.1', port))
            except OSError:
                parser.error(f'Port {port} already occupied; close the previous simulator/OpenOCD first')
    output.mkdir(parents=True, exist_ok=not args.adapter)
    report = {'mode': 'hardware' if args.adapter else 'simulation', 'adapter': args.adapter,
              'started_utc': datetime.now(timezone.utc).isoformat(), 'status': 'running',
              'input_sha256': hashes, 'requested_tests': list(tests), 'full_suite_passed': False,
              'results': {}, 'fpga_configuration': 'not performed',
              'local_bitstream_hash_is_not_device_attestation': True}
    report_file = output / ('hardware_validation.json' if args.adapter else 'simulation_validation.json')
    try:
        for test in tests:
            report['results'][test] = {'status': 'running', 'command': openocd_command(args, test, output)}
            report_file.write_text(json.dumps(report, indent=2), encoding='utf-8')
            run_test(args, test, output)
            report['results'][test]['status'] = 'passed'
        report['status'] = 'passed'
        report['full_suite_passed'] = set(tests) == {'core', 'gdb', 'download'}
    except BaseException as error:
        report['status'] = 'failed'
        report['error'] = str(error)
        if report['results']:
            report['results'][test]['status'] = 'failed'
        raise
    finally:
        report['ended_utc'] = datetime.now(timezone.utc).isoformat()
        report_file.write_text(json.dumps(report, indent=2), encoding='utf-8')
        print(f'Validation evidence: {report_file}', flush=True)


if __name__ == '__main__':
    main()
