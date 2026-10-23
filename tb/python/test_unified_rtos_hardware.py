"""Host-only checks for the unified UART observation modes."""

from contextlib import redirect_stdout
import io
import time
import unittest
from unittest.mock import patch

from validate_unified_rtos_hardware import (observe_heartbeat_soak,
                                            observe_heartbeats, validate_boot,
                                            validate_boot_cycles)


class LinePort:
    def __init__(self, lines):
        self.lines = iter(lines)

    def readline(self):
        return next(self.lines, b'')


class ClockedLinePort(LinePort):
    def __init__(self, lines, clock, interval=1):
        super().__init__(lines)
        self.clock = clock
        self.interval = interval

    def readline(self):
        self.clock[0] += self.interval
        return super().readline()


class BytePort:
    def __init__(self, data):
        self.data = iter(bytes([byte]) for byte in data)
        self.written = bytearray()

    def read(self, count):
        return next(self.data, b'')

    def write(self, data):
        self.written.extend(data)


class ClockedBytePort(BytePort):
    def __init__(self, data, clock):
        super().__init__(data)
        self.clock = clock

    def read(self, count):
        self.clock[0] += 0.01
        return super().read(count)


class UnifiedRtosHardwareTests(unittest.TestCase):
    def test_boot_marker_survives_power_cycle_line_noise(self):
        lines = [
            b'noise\r\n',
            b'\x00\xffBOOT FLASH\r\n',
            b'FREERTOS START V11.1.0 RV32IM 64K tick=1000Hz\r\n',
            b'UART IRQ PASS count=1\r\n',
            b'FREERTOS PASS tick=76 switches=86 queue=16 msip=1 plic=1 uart=1\r\n',
            b'RTOS ALIVE tick=1085 queue=217\r\n',
            b'RTOS ALIVE tick=2089 queue=418\r\n',
            b'RTOS ALIVE tick=3091 queue=619\r\n',
        ]
        port = BytePort(b''.join(lines))
        captured = bytearray()
        report = {}
        with patch('validate_unified_rtos_hardware.validate_output',
                   return_value={'uart': 1, 'tick': 76, 'queue': 16}):
            with redirect_stdout(io.StringIO()):
                validate_boot(port, time.monotonic() + 1, captured, report)
        self.assertEqual(2, report['preboot_prefix_bytes_discarded'])
        self.assertEqual(b'R', bytes(port.written))
        self.assertEqual(b''.join(lines[1:])[2:], bytes(captured))
        self.assertEqual(3, len(report['alive_samples']))

    def test_late_boot_gets_time_for_three_heartbeats(self):
        data = b''.join([
            b'BOOT FLASH\r\n',
            b'FREERTOS START V11.1.0 RV32IM 64K tick=1000Hz\r\n',
            b'UART IRQ PASS count=1\r\n',
            b'FREERTOS PASS tick=76 switches=86 queue=16 msip=1 plic=1 uart=1\r\n',
            b'RTOS ALIVE tick=1085 queue=217\r\n',
            b'RTOS ALIVE tick=2089 queue=418\r\n',
            b'RTOS ALIVE tick=3091 queue=619\r\n',
        ])
        clock = [0.0]
        port = ClockedBytePort(data, clock)
        report = {}
        with patch('validate_unified_rtos_hardware.time.monotonic', side_effect=lambda: clock[0]):
            with patch('validate_unified_rtos_hardware.validate_output',
                       return_value={'uart': 1, 'tick': 76, 'queue': 16}):
                with redirect_stdout(io.StringIO()):
                    validate_boot(port, 0.2, bytearray(), report)
        self.assertGreater(clock[0], 0.2)
        self.assertEqual(3, len(report['alive_samples']))

    def test_missing_boot_preserves_preboot_bytes_for_diagnosis(self):
        data = b'RTOS ALIVE tick=100 queue=20\r\npartial'
        clock = [0.0]
        port = ClockedBytePort(data, clock)
        captured = bytearray()
        report = {}
        with patch('validate_unified_rtos_hardware.time.monotonic', side_effect=lambda: clock[0]):
            with redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(RuntimeError, 'Incomplete FreeRTOS boot'):
                    validate_boot(port, 1, captured, report)
        self.assertEqual(data, bytes(captured))
        self.assertEqual(1, report['preboot_lines_seen'])

    def test_running_heartbeats_are_captured_without_boot_claim(self):
        lines = [
            b'RTOS ALIVE tick=100 queue=20\r\n',
            b'RTOS ALIVE tick=200 queue=40\r\n',
            b'RTOS ALIVE tick=300 queue=60\r\n',
        ]
        captured = bytearray()
        with redirect_stdout(io.StringIO()):
            samples = observe_heartbeats(LinePort(lines), time.monotonic() + 1, captured)
        self.assertEqual([100, 200, 300], [item['tick'] for item in samples])
        self.assertEqual(b''.join(lines), bytes(captured))

    def test_rejects_non_increasing_heartbeat(self):
        lines = [b'RTOS ALIVE tick=100 queue=20\r\n', b'RTOS ALIVE tick=101 queue=20\r\n']
        with redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(RuntimeError, 'did not progress'):
                observe_heartbeats(LinePort(lines), time.monotonic() + 1, bytearray())

    def test_rejects_failure_output(self):
        with redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(RuntimeError, 'Unexpected application output'):
                observe_heartbeats(LinePort([b'FREERTOS FAIL\r\n']),
                                   time.monotonic() + 1, bytearray())

    def test_rejects_missing_heartbeats(self):
        with redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(RuntimeError, 'Three increasing'):
                observe_heartbeats(LinePort([]), time.monotonic() + 0.01, bytearray())

    def test_soak_records_progress_and_gap(self):
        clock = [0.0]
        lines = [f'RTOS ALIVE tick={n * 1000} queue={n * 200}\r\n'.encode()
                 for n in range(1, 5)]
        captured = bytearray()
        with patch('validate_unified_rtos_hardware.time.monotonic', side_effect=lambda: clock[0]):
            with redirect_stdout(io.StringIO()):
                report = observe_heartbeat_soak(ClockedLinePort(lines, clock), 3, captured)
        self.assertEqual(4, report['count'])
        self.assertEqual(1, report['largest_gap_seconds'])
        self.assertEqual(3, report['observed_seconds'])
        self.assertEqual(b''.join(lines), bytes(captured))

    def test_soak_rejects_missing_heartbeat(self):
        clock = [0.0]
        with patch('validate_unified_rtos_hardware.time.monotonic', side_effect=lambda: clock[0]):
            with redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(RuntimeError, 'No FreeRTOS heartbeat'):
                    observe_heartbeat_soak(ClockedLinePort([], clock), 10, bytearray(), max_gap=2)

    def test_soak_rejects_reboot(self):
        clock = [0.0]
        lines = [b'RTOS ALIVE tick=100 queue=20\r\n', b'BOOT FLASH\r\n']
        with patch('validate_unified_rtos_hardware.time.monotonic', side_effect=lambda: clock[0]):
            with redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(RuntimeError, 'Unexpected reboot'):
                    observe_heartbeat_soak(ClockedLinePort(lines, clock), 10, bytearray())

    def test_soak_rejects_counter_regression(self):
        clock = [0.0]
        lines = [b'RTOS ALIVE tick=100 queue=20\r\n', b'RTOS ALIVE tick=101 queue=19\r\n']
        with patch('validate_unified_rtos_hardware.time.monotonic', side_effect=lambda: clock[0]):
            with redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(RuntimeError, 'did not progress'):
                    observe_heartbeat_soak(ClockedLinePort(lines, clock), 10, bytearray())

    def test_two_cold_boots_need_two_complete_sequences(self):
        boot = b''.join([
            b'BOOT FLASH\r\n',
            b'FREERTOS START V11.1.0 RV32IM 64K tick=1000Hz\r\n',
            b'UART IRQ PASS count=1\r\n',
            b'FREERTOS PASS tick=76 switches=86 queue=16 msip=1 plic=1 uart=1\r\n',
            b'RTOS ALIVE tick=1085 queue=217\r\n',
            b'RTOS ALIVE tick=2089 queue=418\r\n',
            b'RTOS ALIVE tick=3091 queue=619\r\n',
        ])
        port = BytePort(boot + boot)
        records = []
        captured = bytearray()
        with patch('validate_unified_rtos_hardware.validate_output',
                   return_value={'uart': 1, 'tick': 76, 'queue': 16}):
            with redirect_stdout(io.StringIO()):
                validate_boot_cycles(port, 2, 1, captured, records)
        self.assertEqual(['passed', 'passed'], [record['status'] for record in records])
        self.assertEqual(2, len(records))
        self.assertEqual(2, bytes(port.written).count(b'R'))
        self.assertEqual(boot + boot, bytes(captured))

    def test_failed_second_cycle_keeps_first_result(self):
        records = []
        with patch('validate_unified_rtos_hardware.validate_boot',
                   side_effect=[None, RuntimeError('second boot failed')]):
            with redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(RuntimeError, 'second boot failed'):
                    validate_boot_cycles(BytePort(b''), 2, 1, bytearray(), records)
        self.assertEqual(['passed', 'failed'], [record['status'] for record in records])


if __name__ == '__main__':
    unittest.main()
