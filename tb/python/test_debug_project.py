import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import xml.etree.ElementTree as ET

import prepare_td_project as prepare


class DebugProjectTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        source_root = prepare.ROOT
        for relative in (
            'rtl/common/uart_wb.v', 'rtl/common/uart_rx.v', 'rtl/common/uart_tx.v',
            'rtl/common/fifo.v', 'rtl/ip/sys_pll.v',
            'rtl/stage3/stage3_top.v', 'rtl/stage3/stage3_debug_top.v',
            'rtl/stage3/stage3_memory.v',
            'constraints/debug.adc', 'constraints/debug.sdc',
            'constraints/uart.adc', 'constraints/uart.sdc',
        ):
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((source_root / relative).read_bytes())
        self.stage3 = self.root / 'build/stage3'
        self.stage3.mkdir(parents=True)
        (self.stage3 / 'bootrom_init.vh').write_text('// Test ROM initialization\n', encoding='ascii')
        self.cpu = self.root / 'cpu.v'
        self.cpu.write_text('module VexRiscvDebug;\nendmodule\n', encoding='ascii')

    def generate(self, variant):
        with patch.object(prepare, 'ROOT', self.root), patch('sys.argv',
                ['prepare_td_project.py', variant, '--cpu', str(self.cpu)]):
            prepare.main()

    def test_debug_project_is_separate_and_only_wraps_hardware_cpu(self):
        sentinel = self.stage3 / 'stage3_uart.prj'
        sentinel.write_text('Existing UART project', encoding='ascii')
        original_cpu = self.cpu.read_bytes()
        self.generate('stage3_debug')
        output = self.root / 'build/debug'
        project = ET.parse(output / 'stage3_debug.prj').getroot()
        self.assertEqual(project.findtext('TOP_MODULE/MODULE'), 'stage3_debug_top')
        sources = [Path(item.attrib['Path']) for item in project.findall('Source_Files/Verilog/File')]
        self.assertIn(output / 'VexRiscvDebug_hw.v', sources)
        self.assertNotIn(self.cpu, sources)
        hardware_cpu = (output / 'VexRiscvDebug_hw.v').read_text()
        self.assertTrue(hardware_cpu.startswith('`define SYNTHESIS\n'))
        self.assertTrue(hardware_cpu.endswith('`undef SYNTHESIS\n'))
        self.assertEqual(self.cpu.read_bytes(), original_cpu)
        self.assertEqual(sentinel.read_text(), 'Existing UART project')
        self.assertIn('// Test ROM initialization', (output / 'stage3_memory_hw.v').read_text())
        sdc = project.find('Source_Files/SDC_FILE/File').attrib['Path']
        self.assertEqual(Path(sdc), self.root / 'constraints/debug.sdc')

    def test_uart_project_keeps_original_cpu_and_constraints(self):
        self.generate('stage3_uart')
        project = ET.parse(self.stage3 / 'stage3_uart.prj').getroot()
        self.assertEqual(project.findtext('TOP_MODULE/MODULE'), 'stage3_top')
        sources = [Path(item.attrib['Path']) for item in project.findall('Source_Files/Verilog/File')]
        self.assertIn(self.cpu, sources)
        self.assertFalse((self.stage3 / 'VexRiscvDebug_hw.v').exists())
        sdc = project.find('Source_Files/SDC_FILE/File').attrib['Path']
        self.assertEqual(Path(sdc), self.root / 'constraints/uart.sdc')


if __name__ == '__main__':
    unittest.main()
