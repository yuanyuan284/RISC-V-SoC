"""Host-only safety checks for live unified GDB inspection."""

from contextlib import redirect_stdout
import io
import json
import sys
import unittest
from unittest.mock import patch

import validate_unified_gdb_hardware as live


class FakeSocket:
    def __init__(self):
        self.sent = bytearray()

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def settimeout(self, _seconds):
        pass

    def sendall(self, data):
        self.sent.extend(data)

    def recv(self, _size):
        return b'\x1a'


class UnifiedGdbHardwareTests(unittest.TestCase):
    def test_plan_only_does_not_start_hardware_tools(self):
        output = io.StringIO()
        with patch.object(sys, 'argv', ['validate_unified_gdb_hardware.py', '--plan-only']):
            with patch.object(live, 'check_ports_free', side_effect=AssertionError('hardware touched')):
                with redirect_stdout(output):
                    live.main()
        plan = json.loads(output.getvalue())
        self.assertEqual('plan_only', plan['mode'])
        self.assertFalse(plan['would_write_ram_or_flash'])
        self.assertIn('board-iotelic-ft2232h.cfg', ' '.join(plan['openocd']))

    def test_recovery_command_uses_openocd_tcl_delimiter(self):
        client = FakeSocket()
        with patch.object(live.socket, 'create_connection', return_value=client):
            self.assertEqual('', live.openocd_tcl('resume'))
        self.assertEqual(b'resume\x1a', bytes(client.sent))

    def test_gdb_script_resumes_before_detach_and_never_downloads(self):
        commands = [line.strip() for line in live.GDB_SCRIPT.read_text().splitlines()]
        self.assertLess(commands.index('monitor resume'), commands.index('detach'))
        for forbidden in ('load', 'restore', 'set ', 'monitor reset', 'monitor flash'):
            self.assertFalse(any(line.startswith(forbidden) for line in commands
                                 if not line.startswith('set pagination') and
                                 not line.startswith('set confirm')))


if __name__ == '__main__':
    unittest.main()
