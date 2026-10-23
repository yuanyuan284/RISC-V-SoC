"""Host-only gates for the destructive unified JTAG hardware regression."""

from contextlib import redirect_stderr, redirect_stdout
import io
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

import validate_unified_full_debug_hardware as full


class UnifiedFullDebugHardwareTests(unittest.TestCase):
    class FakePort:
        fail_clear = False

        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

        def open(self):
            pass

        def reset_input_buffer(self):
            if self.fail_clear:
                raise OSError('serial buffer unavailable')

    def test_plan_only_never_opens_hardware(self):
        output = io.StringIO()
        with patch.object(sys, 'argv', ['validate_unified_full_debug_hardware.py', '--plan-only']), \
                patch.object(full, 'check_ports_free', side_effect=AssertionError('hardware touched')), \
                patch.object(full.subprocess, 'run', side_effect=AssertionError('process started')), \
                redirect_stdout(output):
            full.main()
        plan = json.loads(output.getvalue())
        self.assertEqual(65536, plan['ram_overwrite_bytes'])
        self.assertFalse(plan['flash_writes'])
        self.assertTrue(plan['unified_identity_required'])
        self.assertEqual(['core', 'gdb', 'download'], plan['commands']['tests'])

    def test_overwrite_gate_precedes_input_or_hardware_access(self):
        with patch.object(sys, 'argv', ['validate_unified_full_debug_hardware.py']), \
                patch.object(full, 'check_ports_free', side_effect=AssertionError('hardware touched')), \
                patch.object(full.subprocess, 'run', side_effect=AssertionError('process started')), \
                redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as error:
                full.main()
        self.assertEqual(2, error.exception.code)

    def test_recovery_script_only_resets_cpu_and_never_writes_flash(self):
        commands = [line.strip() for line in full.RECOVERY.read_text().splitlines()]
        self.assertEqual('reset run', commands[2])
        self.assertNotIn('program', ' '.join(commands).lower())
        self.assertNotIn('flash', ' '.join(commands).lower())

    def test_evidence_hashes_unified_cpu_and_constraints(self):
        for path in ('build/cpu-unified/VexRiscvUnified.v',
                     'rtl/stage3/stage3_unified_top.v',
                     'constraints/debug.adc', 'constraints/debug.sdc'):
            self.assertIn(path, full.INPUTS)

    def test_elf_loads_must_stay_in_ram(self):
        path = full.ROOT / 'build/debug/debug_demo.elf'
        full.require_ram_only_elf(path)
        data = bytearray(path.read_bytes())
        phoff = full.ELF_HEADER.unpack_from(data)[5]
        struct.pack_into('<I', data, phoff + full.PROGRAM_HEADER.size + 12, 0x30050000)
        with tempfile.TemporaryDirectory() as directory:
            invalid = Path(directory) / 'outside_ram.elf'
            invalid.write_bytes(data)
            with self.assertRaisesRegex(ValueError, 'outside RAM'):
                full.require_ram_only_elf(invalid)

    def test_failed_ram_test_still_attempts_recovery_and_cannot_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = io.StringIO()
            port = self.FakePort()
            with patch.object(sys, 'argv', ['validate_unified_full_debug_hardware.py',
                                            '--confirm-ram-overwrite']), \
                    patch.object(full, 'ROOT', root), \
                    patch.object(full, 'INPUTS', ()), \
                    patch.object(full, 'require_ram_only_elf'), \
                    patch.object(full, 'check_ports_free'), \
                    patch('serial.Serial', return_value=port), \
                    patch.object(full, 'openocd_script', side_effect=[
                        (0, 'UNIFIED_IDENTITY_OK'), (0, 'UNIFIED_RESET_RUN_SENT')]) as ocd, \
                    patch.object(full, 'run_test', side_effect=RuntimeError('injected RAM failure')), \
                    patch.object(full, 'validate_boot') as boot, \
                    redirect_stdout(output):
                with self.assertRaisesRegex(RuntimeError, 'injected RAM failure'):
                    full.main()
            report = json.loads(next(root.rglob('report.json')).read_text())
            self.assertEqual('failed', report['status'])
            self.assertFalse(report['full_suite_passed'])
            self.assertEqual({'core': 'failed'}, report['tests'])
            self.assertTrue(report['cpu_reset_run_sent'])
            self.assertTrue(report['boot_sequence_observed'])
            self.assertEqual(2, ocd.call_count)
            boot.assert_called_once()

    def test_serial_clear_failure_does_not_skip_cpu_reset(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            port = self.FakePort()
            port.fail_clear = True
            with patch.object(sys, 'argv', ['validate_unified_full_debug_hardware.py',
                                            '--confirm-ram-overwrite']), \
                    patch.object(full, 'ROOT', root), \
                    patch.object(full, 'INPUTS', ()), \
                    patch.object(full, 'require_ram_only_elf'), \
                    patch.object(full, 'check_ports_free'), \
                    patch('serial.Serial', return_value=port), \
                    patch.object(full, 'openocd_script', side_effect=[
                        (0, 'UNIFIED_IDENTITY_OK'), (0, 'UNIFIED_RESET_RUN_SENT')]) as ocd, \
                    patch.object(full, 'run_test'), \
                    patch.object(full, 'validate_boot'), \
                    redirect_stdout(io.StringIO()):
                full.main()
            report = json.loads(next(root.rglob('report.json')).read_text())
            self.assertTrue(report['full_suite_passed'])
            self.assertEqual('serial buffer unavailable', report['serial_clear_error'])
            self.assertTrue(report['cpu_reset_run_sent'])
            self.assertEqual(2, ocd.call_count)
            self.assertTrue(next(root.rglob('uart_boot.log')).is_file())


if __name__ == '__main__':
    unittest.main()
