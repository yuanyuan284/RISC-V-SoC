"""Run the full RAM/GDB regression on the unified FPGA image, then reboot XIP."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import struct
from types import SimpleNamespace
import subprocess
import time

from validate_debug_sim import run_test
from validate_unified_gdb_hardware import check_ports_free
from validate_unified_rtos_hardware import validate_boot

ROOT = Path(__file__).resolve().parents[1]
IDENTITY = ROOT / 'script/openocd/probe-unified-identity.tcl'
RECOVERY = ROOT / 'script/openocd/reset-unified-run.tcl'
INPUTS = (
    'build/unified/stage3_unified.bit',
    'build/unified/freertos_xip.xip',
    'build/cpu-unified/VexRiscvUnified.v',
    'rtl/stage3/stage3_unified_top.v',
    'constraints/debug.adc',
    'constraints/debug.sdc',
    'build/debug/debug_demo.elf',
    'build/stage3/app_a.elf',
    'script/openocd/board-iotelic-ft2232h.cfg',
    'script/openocd/iotelic-ft2232h.cfg',
    'script/openocd/riscv-debug.cfg',
    'script/openocd/probe-unified-identity.tcl',
    'script/openocd/reset-unified-run.tcl',
    'script/openocd/validate-debug.tcl',
    'script/openocd/validate-download.tcl',
    'script/gdb/validate-debug.gdb',
    'script/unified_td.tcl',
)
ELF_HEADER = struct.Struct('<16sHHIIIIIHHHHHH')
PROGRAM_HEADER = struct.Struct('<IIIIIIII')
RAM_START = 0x80000000
RAM_END = 0x80010000


def require_ram_only_elf(path):
    data = path.read_bytes()
    if len(data) < ELF_HEADER.size:
        raise ValueError(f'Truncated ELF: {path}')
    header = ELF_HEADER.unpack_from(data)
    ident, kind, machine, version, entry, phoff = header[:6]
    phentsize, phnum = header[9:11]
    if (ident[:7] != b'\x7fELF\x01\x01\x01' or kind != 2 or machine != 243 or
            version != 1 or phentsize != PROGRAM_HEADER.size or
            phoff + phnum * phentsize > len(data) or not phnum):
        raise ValueError(f'Unsupported ELF: {path}')
    if not RAM_START <= entry < RAM_END:
        raise ValueError(f'ELF entry is outside RAM: {path}')
    found = False
    for index in range(phnum):
        ptype, offset, vaddr, paddr, filesz, memsz, *_ = PROGRAM_HEADER.unpack_from(
            data, phoff + index * phentsize)
        if ptype != 1 or not memsz:
            continue
        found = True
        if (filesz > memsz or offset + filesz > len(data) or paddr != vaddr or
                paddr < RAM_START or paddr + memsz > RAM_END):
            raise ValueError(f'ELF load segment is outside RAM: {path}')
    if not found:
        raise ValueError(f'ELF has no loadable RAM segment: {path}')


def openocd_script(openocd, script, timeout, log):
    result = subprocess.run([openocd, '-f', str(script)], cwd=ROOT,
                            capture_output=True, text=True, encoding='utf-8',
                            errors='replace', timeout=timeout, check=False)
    output = result.stdout + result.stderr
    log.write_text(output, encoding='utf-8')
    return result.returncode, output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--openocd', default=os.environ.get('OPENOCD', 'openocd'))
    parser.add_argument('--gdb', default=os.environ.get('RISCV_GDB', 'riscv-none-elf-gdb'))
    parser.add_argument('--port', default='COM3')
    parser.add_argument('--timeout', type=int, default=3600)
    parser.add_argument('--confirm-ram-overwrite', action='store_true')
    parser.add_argument('--plan-only', action='store_true')
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    if not args.plan_only and not args.confirm_ram_overwrite:
        parser.error('Full regression overwrites all 64 KiB RAM; add --confirm-ram-overwrite')

    commands = {'identity': [args.openocd, '-f', str(IDENTITY)],
                'tests': ['core', 'gdb', 'download'],
                'recovery': [args.openocd, '-f', str(RECOVERY)]}
    if args.plan_only:
        print(json.dumps({'mode': 'plan_only', 'unified_identity_required': True,
                          'ram_overwrite_bytes': 65536, 'flash_writes': False,
                          'cpu_reset_after_tests': True, 'commands': commands}, indent=2))
        return

    hashes = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
              for name in INPUTS}
    require_ram_only_elf(ROOT / 'build/debug/debug_demo.elf')
    require_ram_only_elf(ROOT / 'build/stage3/app_a.elf')
    check_ports_free()
    import serial

    output = ROOT / 'build/unified/hardware' / datetime.now().strftime(
        'full_debug_%Y%m%d-%H%M%S-%f')
    output.mkdir(parents=True, exist_ok=False)
    report_path = output / 'report.json'
    report = {'mode': 'unified_full_debug_hardware', 'status': 'running',
              'started_utc': datetime.now(timezone.utc).isoformat(),
              'input_sha256': hashes, 'local_hashes_are_not_device_attestation': True,
              'tests': {}, 'cpu_reset_run_sent': False, 'boot_sequence_observed': False,
              'flash_writes': False}
    failure = None
    serial_port = serial.Serial(port=None, baudrate=115200, timeout=1, write_timeout=3)
    serial_port.dtr = False
    serial_port.rts = False
    serial_port.port = args.port
    try:
        serial_port.open()
        with serial_port:
            code, identity = openocd_script(args.openocd, IDENTITY, 60,
                                            output / 'identity.log')
            if code or 'UNIFIED_IDENTITY_OK' not in identity:
                raise RuntimeError('Unified XIP identity probe failed; RAM tests were not started')
            report['unified_identity_confirmed'] = True
            report_path.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')

            legacy_args = SimpleNamespace(adapter='iotelic-ft2232h', openocd=args.openocd,
                                          gdb=args.gdb, timeout=args.timeout, wave=False)
            try:
                for name in commands['tests']:
                    report['tests'][name] = 'running'
                    report_path.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
                    run_test(legacy_args, name, output)
                    report['tests'][name] = 'passed'
            except BaseException as error:
                report['tests'][name] = 'failed'
                failure = error
            finally:
                boot_bytes = bytearray()
                try:
                    try:
                        serial_port.reset_input_buffer()
                    except Exception as error:
                        report['serial_clear_error'] = str(error)
                    code, recovery = openocd_script(args.openocd, RECOVERY, 60,
                                                    output / 'recovery.log')
                    if code or 'UNIFIED_RESET_RUN_SENT' not in recovery:
                        raise RuntimeError('Could not send CPU reset run after RAM tests')
                    report['cpu_reset_run_sent'] = True
                    validate_boot(serial_port, time.monotonic() + 180, boot_bytes, report)
                    report['boot_sequence_observed'] = True
                except BaseException as error:
                    if failure is None:
                        failure = error
                    report['recovery_error'] = str(error)
                finally:
                    (output / 'uart_boot.log').write_bytes(boot_bytes)
    except BaseException as error:
        if failure is None:
            failure = error
    finally:
        report['status'] = 'passed' if failure is None else 'failed'
        report['full_suite_passed'] = (failure is None and
                                       set(report['tests']) == set(commands['tests']) and
                                       all(value == 'passed' for value in report['tests'].values()) and
                                       report['boot_sequence_observed'])
        if failure is not None:
            report['error'] = str(failure)
        report['ended_utc'] = datetime.now(timezone.utc).isoformat()
        report_path.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
        print(f'UNIFIED_FULL_DEBUG_REPORT: {report_path}', flush=True)
    if failure is not None:
        raise failure
    print('UNIFIED_FULL_DEBUG_PASS', flush=True)


if __name__ == '__main__':
    main()
