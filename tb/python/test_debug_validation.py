from contextlib import redirect_stdout, redirect_stderr
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import validate_debug_sim as validation


class DebugValidationTests(unittest.TestCase):
    def metadata_fixture(self, test, results):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            # Isolated host fixture, never physical-device validation evidence.
            with patch.object(validation, 'ROOT', root), \
                    patch.object(validation, 'BUILD', root / 'build/debug'), \
                    patch.object(validation, 'input_hashes', return_value={'unit_fixture': 'not-device-evidence'}), \
                    patch.object(validation, 'run_test', side_effect=results), \
                    patch.object(validation.socket, 'socket'), \
                    patch('sys.argv', ['validate_debug_sim.py', '--adapter', 'jlink',
                                       '--confirm-ram-overwrite', '--test', test]), \
                    redirect_stdout(io.StringIO()):
                try:
                    validation.main()
                except RuntimeError:
                    pass
            reports = list(root.rglob('hardware_validation.json'))
            self.assertEqual(len(reports), 1)
            return json.loads(reports[0].read_text(encoding='utf-8'))

    def test_a_partial_suite_cannot_be_reported_as_full_acceptance(self):
        report = self.metadata_fixture('core', [None])
        self.assertEqual(report['status'], 'passed')
        self.assertEqual(report['requested_tests'], ['core'])
        self.assertFalse(report['full_suite_passed'])
        self.assertEqual(report['fpga_configuration'], 'not performed')

    def test_failure_retains_prior_results_and_never_reports_full_success(self):
        report = self.metadata_fixture('all', [None, RuntimeError('Injected unit-test failure')])
        self.assertEqual(report['status'], 'failed')
        self.assertFalse(report['full_suite_passed'])
        self.assertEqual(report['results']['core']['status'], 'passed')
        self.assertEqual(report['results']['gdb']['status'], 'failed')
        self.assertNotIn('download', report['results'])
        self.assertIn('Injected unit-test failure', report['error'])
        self.assertIn('ended_utc', report)

    def test_all_markers_are_required_and_failure_text_is_rejected(self):
        for test, markers in validation.TEST_MARKERS.items():
            with self.subTest(test=test):
                good = '\n'.join(markers)
                validation.validate_log(test, good)
                with self.assertRaises(RuntimeError):
                    validation.validate_log(test, '')
                if len(markers) > 1:
                    with self.assertRaises(RuntimeError):
                        validation.validate_log(test, '\n'.join(markers[:-1]))
                for failure in ('FAIL assertion', 'MIS-MATCHED'):
                    with self.assertRaises(RuntimeError):
                        validation.validate_log(test, good + '\n' + failure)

    def test_simulation_and_hardware_commands_select_different_transports(self):
        args = SimpleNamespace(openocd='openocd', adapter=None)
        output = Path('D:/project/build/debug')
        simulated = validation.openocd_command(args, 'core', output)
        self.assertIn('script/openocd/simulation.cfg', simulated)
        for adapter, config in validation.ADAPTER_CONFIGS.items():
            args.adapter = adapter
            for test in ('core', 'gdb', 'download'):
                command = validation.openocd_command(args, test, output)
                self.assertIn(config, command)
                self.assertNotIn('script/openocd/simulation.cfg', command)
                self.assertNotIn('configure_debug_fpga.tcl', command)
                if test == 'download':
                    self.assertIn(f'set validation_output {{{output.as_posix()}}}', command)

    def test_hardware_without_overwrite_acknowledgment_cannot_start_processes(self):
        for adapter in validation.ADAPTER_CONFIGS:
            with self.subTest(adapter=adapter), \
                    patch('sys.argv', ['validate_debug_sim.py', '--adapter', adapter]), \
                    patch.object(validation.subprocess, 'Popen') as popen, \
                    patch.object(validation, 'input_hashes') as hashes, redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as result:
                    validation.main()
                self.assertEqual(result.exception.code, 2)
                hashes.assert_not_called()
                popen.assert_not_called()

    def test_wave_capture_rejects_hardware_before_starting_processes(self):
        with patch('sys.argv', ['validate_debug_sim.py', '--adapter', 'jlink',
                                 '--confirm-ram-overwrite', '--wave']), \
                patch.object(validation.subprocess, 'Popen') as popen, \
                patch.object(validation, 'input_hashes') as hashes, \
                redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as result:
                validation.main()
        self.assertEqual(result.exception.code, 2)
        hashes.assert_not_called()
        popen.assert_not_called()

    def test_plan_only_starts_nothing_and_is_not_passed_evidence(self):
        for adapter in validation.ADAPTER_CONFIGS:
            output = io.StringIO()
            with self.subTest(adapter=adapter), \
                    patch('sys.argv', ['validate_debug_sim.py', '--adapter', adapter, '--plan-only']), \
                    patch.object(validation.subprocess, 'Popen') as popen, \
                    patch.object(validation, 'input_hashes') as hashes, redirect_stdout(output):
                validation.main()
                popen.assert_not_called()
                hashes.assert_not_called()
            plan = json.loads(output.getvalue())
            self.assertEqual(plan['mode'], 'hardware')
            self.assertEqual(plan['adapter'], adapter)
            self.assertNotIn('status', plan)
            self.assertEqual(plan['fpga_configuration'], 'not performed')
            self.assertEqual([item['test'] for item in plan['commands']], ['core', 'gdb', 'download'])

    def test_iotelic_bringup_does_not_drive_auxiliary_gpio(self):
        config = (validation.ROOT / 'script/openocd/iotelic-ft2232h.cfg').read_text()
        commands = [line.strip() for line in config.splitlines()
                    if line.strip() and not line.lstrip().startswith('#')]
        self.assertEqual(commands, ['adapter driver ftdi', 'ftdi vid_pid 0x15ba 0x002a',
                                   'ftdi channel 0', 'ftdi layout_init 0x0008 0x000b',
                                   'adapter speed 100'])
        probe = (validation.ROOT / 'script/openocd/probe-iotelic-tap.cfg').read_text()
        self.assertIn('jtag newtap soc cpu -irlen 5 -expected-id 0x10002fff', probe)
        self.assertIn('\njtag arp_init\n', probe)
        self.assertNotIn('target create', probe)
        self.assertNotIn('riscv-debug.cfg', probe)

    def test_iotelic_evidence_hashes_include_the_interface_config(self):
        with patch.object(Path, 'read_bytes', return_value=b'unit-test fixture') as read:
            hashes = validation.input_hashes(('core',), 'iotelic-ft2232h')
        self.assertIn('script/openocd/iotelic-ft2232h.cfg', hashes)
        self.assertIn('script/openocd/board-iotelic-ft2232h.cfg', hashes)
        self.assertEqual(read.call_count, len(hashes))

    def test_hardware_mode_never_launches_an_rtl_bridge(self):
        args = SimpleNamespace(adapter='jlink', openocd='openocd', timeout=60)
        with patch.object(validation, 'LoggedProcess') as process, \
                patch.object(validation, 'validate_log') as check, \
                patch.object(Path, 'read_text', return_value='mocked unit-test log'):
            validation.run_test(args, 'core')
            process.assert_called_once()
            command = process.call_args.args[0]
            self.assertEqual(command[0], 'openocd')
            self.assertIn('script/openocd/board-jlink.cfg', command)
            check.assert_called_once_with('core', 'mocked unit-test log')
            process.return_value.stop.assert_called_once()

    def test_failed_log_still_cleans_up_the_owned_process(self):
        args = SimpleNamespace(adapter='jlink', openocd='openocd', timeout=60)
        with patch.object(validation, 'LoggedProcess') as process, \
                patch.object(Path, 'read_text', return_value='incomplete unit-test log'):
            process.return_value.proc.poll.return_value = 0
            with self.assertRaises(RuntimeError):
                validation.run_test(args, 'core')
            process.return_value.stop.assert_called_once()


if __name__ == '__main__':
    unittest.main()
