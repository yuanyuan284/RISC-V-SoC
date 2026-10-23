"""Observe a fresh unified XIP boot and sustained FreeRTOS activity on UART."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'build/deps/pyserial'))
from validate_rtos_hardware import validate_output

BOOT = b'BOOT FLASH\r\n'
START = b'FREERTOS START V11.1.0 RV32IM 64K tick=1000Hz\r\n'
IRQ = re.compile(rb'UART IRQ PASS count=(\d+)\r\n')
ALIVE = re.compile(rb'RTOS ALIVE tick=(\d+) queue=(\d+)\r\n')


def observe_heartbeats(port, deadline, captured, required=3):
    samples = []
    while time.monotonic() < deadline and len(samples) < required:
        line = port.readline()
        if not line:
            continue
        captured.extend(line)
        print(line.decode('ascii', errors='replace').rstrip(), flush=True)
        if b'FREERTOS FAIL' in line or b'BOOT UART' in line:
            raise RuntimeError(f'Unexpected application output: {line!r}')
        match = ALIVE.fullmatch(line)
        if not match:
            continue
        tick, queued = map(int, match.groups())
        if samples and (tick <= samples[-1]['tick'] or queued <= samples[-1]['queue']):
            raise RuntimeError('Scheduler heartbeat did not progress')
        samples.append({'tick': tick, 'queue': queued})
    if len(samples) < required:
        raise RuntimeError('Three increasing FreeRTOS heartbeats were not observed')
    return samples


def observe_heartbeat_soak(port, seconds, captured, max_gap=5):
    first_seen = None
    last_seen = time.monotonic()
    last_sample = None
    count = 0
    largest_gap = 0.0
    while first_seen is None or time.monotonic() - first_seen < seconds:
        line = port.readline()
        now = time.monotonic()
        if line:
            captured.extend(line)
            if b'BOOT FLASH' in line or b'FREERTOS START' in line:
                raise RuntimeError('Unexpected reboot during heartbeat soak')
            if b'FREERTOS FAIL' in line or b'BOOT UART' in line:
                raise RuntimeError(f'Unexpected application output: {line!r}')
            match = ALIVE.fullmatch(line)
            if match:
                tick, queued = map(int, match.groups())
                if last_sample and (tick <= last_sample['tick'] or queued <= last_sample['queue']):
                    raise RuntimeError('Scheduler heartbeat did not progress')
                if first_seen is None:
                    first_seen = now
                    first_sample = {'tick': tick, 'queue': queued}
                else:
                    largest_gap = max(largest_gap, now - last_seen)
                last_seen = now
                last_sample = {'tick': tick, 'queue': queued}
                count += 1
                if count == 1 or count % 30 == 0:
                    print(f'HEARTBEAT {count}: tick={tick} queue={queued}', flush=True)
        if now - last_seen > max_gap:
            raise RuntimeError(f'No FreeRTOS heartbeat for more than {max_gap} seconds')
    if count < 2:
        raise RuntimeError('Heartbeat soak captured fewer than two samples')
    return {'requested_seconds': seconds, 'observed_seconds': round(last_seen - first_seen, 3),
            'count': count, 'first': first_sample, 'last': last_sample,
            'largest_gap_seconds': round(largest_gap, 3)}


def validate_boot_cycles(port, cycles, timeout, captured, records):
    for number in range(1, cycles + 1):
        print(f'LISTEN_READY: power-cycle EF2 board for cycle {number}/{cycles}', flush=True)
        cycle_capture = bytearray()
        record = {'cycle': number, 'status': 'running'}
        records.append(record)
        try:
            validate_boot(port, time.monotonic() + timeout, cycle_capture, record)
            record['status'] = 'passed'
            print(f'CYCLE_PASS: {number}/{cycles}', flush=True)
        except BaseException as error:
            record['status'] = 'failed'
            record['error'] = str(error)
            raise
        finally:
            captured.extend(cycle_capture)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', default='COM3')
    parser.add_argument('--timeout', type=int, default=300)
    parser.add_argument('--trigger', choices=('cpu-reset', 'power-cycle'), default='cpu-reset')
    parser.add_argument('--observe-running', action='store_true',
                        help='Capture current heartbeats only; do not claim a boot test')
    parser.add_argument('--soak-seconds', type=int, default=0,
                        help='Continuously observe running heartbeats for this many seconds')
    parser.add_argument('--cycles', type=int, default=1,
                        help='Number of separate operator-triggered power cycles to validate')
    args = parser.parse_args()
    if args.soak_seconds < 0 or (args.soak_seconds and args.observe_running):
        parser.error('--soak-seconds must be positive and cannot be combined with --observe-running')
    if args.cycles < 1 or (args.cycles > 1 and
                           (args.trigger != 'power-cycle' or args.observe_running or args.soak_seconds)):
        parser.error('Multiple cycles require --trigger power-cycle without observation modes')
    import serial

    output_dir = ROOT / 'build/unified/hardware'
    output_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime('%Y%m%d-%H%M%S')
    log_path = output_dir / f'rtos_uart_{stamp}.log'
    report_path = output_dir / f'rtos_uart_{stamp}.json'
    report = {
        'mode': ('hardware_uart_cold_boot_cycles' if args.cycles > 1 else
                 'hardware_uart_soak' if args.soak_seconds else
                 'hardware_uart_liveness_only' if args.observe_running else
                 f'hardware_uart_after_{args.trigger.replace("-", "_")}'),
        'status': 'running',
        'port': args.port,
        'local_bitstream_sha256': hashlib.sha256(
            (ROOT / 'build/unified/stage3_unified.bit').read_bytes()).hexdigest(),
        'xip_image_sha256': hashlib.sha256(
            (ROOT / 'build/unified/freertos_xip.xip').read_bytes()).hexdigest(),
        'local_hashes_are_not_device_attestation': True,
    }
    captured = bytearray()
    try:
        port = serial.Serial(port=None, baudrate=115200, timeout=1, write_timeout=3)
        port.dtr = False
        port.rts = False
        port.port = args.port
        port.open()
        with port:
            port.reset_input_buffer()
            deadline = time.monotonic() + args.timeout
            if args.soak_seconds:
                print('LISTEN_READY: observing sustained FreeRTOS heartbeats', flush=True)
                report['soak'] = observe_heartbeat_soak(port, args.soak_seconds, captured)
                report['boot_sequence_observed'] = False
                report['status'] = 'passed'
            elif args.observe_running:
                print('LISTEN_READY: observing current FreeRTOS heartbeats', flush=True)
                report['alive_samples'] = observe_heartbeats(port, deadline, captured)
                report['boot_sequence_observed'] = False
                report['status'] = 'liveness_observed'
            elif args.cycles > 1:
                report['cycles'] = []
                report['power_cycle_is_operator_reported'] = True
                validate_boot_cycles(port, args.cycles, args.timeout, captured, report['cycles'])
                report['status'] = 'passed'
            else:
                if args.trigger == 'power-cycle':
                    print('LISTEN_READY: power-cycle only the EF2 board now', flush=True)
                else:
                    print('LISTEN_READY: issue CPU JTAG reset run now', flush=True)
                validate_boot(port, deadline, captured, report)
                report['status'] = 'passed'
    except BaseException as error:
        report['status'] = 'failed'
        report['error'] = str(error)
        raise
    finally:
        report['ended_utc'] = datetime.now(timezone.utc).isoformat()
        log_path.write_bytes(bytes(captured))
        report_path.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
        print(f'UART_EVIDENCE: {log_path}', flush=True)
        print(f'UART_REPORT: {report_path}', flush=True)
    print('UNIFIED_RTOS_SOAK_PASS' if args.soak_seconds else
          'UNIFIED_RTOS_LIVENESS_OBSERVED' if args.observe_running else
          'UNIFIED_RTOS_UART_PASS', flush=True)


def validate_boot(port, deadline, captured, report):
    boot = start = irq = passed = False
    alive = []
    pending = bytearray()
    while time.monotonic() < deadline and not (len(alive) >= 3 and irq and passed):
        byte = port.read(1)
        if not byte:
            continue
        pending.extend(byte)
        if byte != b'\n':
            continue
        line = bytes(pending)
        pending.clear()
        if not boot:
            marker = line.find(BOOT)
            if marker < 0:
                captured.extend(line)
                count = report.get('preboot_lines_seen', 0) + 1
                report['preboot_lines_seen'] = count
                if count <= 3:
                    print(f'WAITING_FOR_BOOT: {line[:80]!r}', flush=True)
                continue
            report['preboot_prefix_bytes_discarded'] = marker
            line = line[marker:]
        if line == BOOT:
            if boot:
                raise RuntimeError('Unexpected reboot before FreeRTOS validation completed')
            captured.clear()
            deadline = max(deadline, time.monotonic() + 15)
        captured.extend(line)
        print(line.decode('ascii', errors='replace').rstrip(), flush=True)
        if b'FREERTOS FAIL' in line or b'BOOT UART' in line:
            raise RuntimeError(f'Unexpected boot/application output: {line!r}')
        if line == BOOT:
            boot = True
        elif line == START:
            if not boot:
                raise RuntimeError('FreeRTOS started without the Flash BootROM marker')
            start = True
            port.write(b'R')
        elif (match := IRQ.fullmatch(line)):
            irq = int(match.group(1)) >= 1
        elif line.startswith(b'FREERTOS PASS '):
            report['counters'] = validate_output(bytes(captured))
            passed = True
        elif (match := ALIVE.fullmatch(line)):
            tick, queued = map(int, match.groups())
            previous = alive[-1] if alive else report.get('counters')
            if previous is None or tick <= previous['tick'] or queued <= previous['queue']:
                raise RuntimeError('Scheduler heartbeat did not progress')
            if len(alive) < 3:
                alive.append({'tick': tick, 'queue': queued})
    if pending:
        captured.extend(pending)
    if not (boot and start and irq and passed and len(alive) == 3):
        raise RuntimeError('Incomplete FreeRTOS boot, UART IRQ, self-test, or three heartbeats')
    if report['counters']['uart'] < 1:
        raise RuntimeError('FreeRTOS self-test did not include UART IRQ')
    report['alive_samples'] = alive


if __name__ == '__main__':
    main()
