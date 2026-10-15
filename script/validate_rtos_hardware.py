"""Load FreeRTOS through the real BootROM and check full application evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
from datetime import datetime, timezone
from uart_upload import transfer
from uart_upload_stage3 import BANNER, packet

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'build/deps/pyserial'))
CHECKS = b'CHECK preemption=1 registers=1 critical=1 queue=1 notify=1\r\n'
RESULT = re.compile(rb'FREERTOS PASS tick=(\d+) switches=(\d+) queue=(\d+) msip=(\d+) plic=(\d+) uart=(\d+)\r\n')

def validate_output(output):
    if b'FREERTOS FAIL' in output or CHECKS not in output:
        raise RuntimeError('Missing application assertions or failed FreeRTOS check')
    match = RESULT.search(output)
    if not match:
        raise RuntimeError('Missing complete FreeRTOS result line')
    tick, switches, queue, msip, plic, uart = map(int, match.groups())
    if tick < 60 or switches < 20 or queue < 10 or msip != 1 or plic != 1:
        raise RuntimeError('Application counters do not satisfy acceptance')
    return dict(tick=tick, switches=switches, queue=queue, msip=msip, plic=plic, uart=uart)

class Capture:
    def __init__(self, port):
        self.port = port
        self.output = bytearray()
    @property
    def timeout(self):
        return self.port.timeout
    @timeout.setter
    def timeout(self, value):
        self.port.timeout = value
    def read(self, size):
        return self.port.read(size)
    def write(self, data):
        return self.port.write(data)
    def read_until(self, expected):
        data = self.port.read_until(expected)
        self.output.extend(data)
        return data

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', required=True)
    parser.add_argument('--boot-timeout', type=float, default=90)
    args = parser.parse_args()
    import serial
    build = ROOT / 'build/rtos'
    binary = build / 'freertos.bin'
    report = {'mode': 'hardware', 'status': 'running', 'port': args.port,
              'started_utc': datetime.now(timezone.utc).isoformat(),
              'bin_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
              'local_bit_sha256': hashlib.sha256((build / 'stage3_rtos.bit').read_bytes()).hexdigest(),
              'local_bit_hash_is_not_device_attestation': True}
    capture = None
    try:
        port = serial.Serial(port=None, baudrate=115200, timeout=args.boot_timeout, write_timeout=3)
        port.dtr = False; port.rts = False; port.port = args.port
        port.open()
        with port:
            port.reset_input_buffer()
            capture = Capture(port)
            print('Listening for fresh RTOS BootROM banner', flush=True)
            transfer(capture, packet(binary.read_bytes()), b'FREERTOS PASS', banner=BANNER,
                     progress=lambda done, total: print(f'Uploaded {done}/{total} bytes', flush=True))
            capture.output.extend(port.read_until(b'\n'))
            report['counters'] = validate_output(bytes(capture.output))
            # Require evidence from the notified task, not merely a successful write.
            port.write(b'R')
            print('Initial scheduler checks passed; UART interrupt input sent', flush=True)
            uart_line = port.read_until(b'\n')
            capture.output.extend(uart_line)
            if uart_line != b'UART IRQ PASS count=1\r\n':
                raise RuntimeError(f'UART ISR/task evidence missing: {uart_line!r}')
            report['uart_interrupt_task_passed'] = True
            report['alive_samples'] = []
            for _ in range(3):
                alive = port.read_until(b'\n')
                capture.output.extend(alive)
                match = re.fullmatch(rb'RTOS ALIVE tick=(\d+) queue=(\d+)\r\n', alive)
                if not match:
                    raise RuntimeError(f'Sustained scheduler evidence missing: {alive!r}')
                tick, queued = map(int, match.groups())
                previous = report['alive_samples'][-1] if report['alive_samples'] else report['counters']
                if tick <= previous['tick'] or queued <= previous['queue']:
                    raise RuntimeError('Scheduler tick/queue stopped progressing')
                report['alive_samples'].append(dict(tick=tick, queue=queued))
                print(alive.decode('ascii').strip(), flush=True)
            report['status'] = 'passed'
    except BaseException as error:
        report['status'] = 'failed'; report['error'] = str(error)
        raise
    finally:
        report['ended_utc'] = datetime.now(timezone.utc).isoformat()
        if capture:
            (build / 'hardware_validation.log').write_bytes(bytes(capture.output))
        (build / 'hardware_validation.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2), flush=True)

if __name__ == '__main__':
    main()
