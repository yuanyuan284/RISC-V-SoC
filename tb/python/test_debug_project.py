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
            'rtl/stage3/stage3_flash_top.v', 'rtl/stage3/stage3_flash_read.v',
            'rtl/stage3/stage3_flash_writer.v',
            'rtl/stage3/stage3_unified_top.v',
            'rtl/stage3/stage3_memory.v',
            'rtl/stage3/stage3_rtos_top.v', 'rtl/stage3/rtos_clint.v',
            'rtl/stage3/rtos_plic.v', 'rtl/stage3/rtos_event.v',
            'constraints/debug.adc', 'constraints/debug.sdc',
            'constraints/uart.adc', 'constraints/uart.sdc',
        ):
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((source_root / relative).read_bytes())
        self.stage3 = self.root / 'build/stage3'
        self.stage3.mkdir(parents=True)
        (self.stage3 / 'bootrom_init.vh').write_text('// Test ROM initialization\n', encoding='ascii')
        flash = self.root / 'build/flash'
        flash.mkdir(parents=True)
        (flash / 'bootrom_init.vh').write_text('// Flash ROM initialization\n', encoding='ascii')
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

    def test_flash_project_is_separate_and_uses_debug_cpu(self):
        original_cpu = self.cpu.read_bytes()
        self.generate('stage3_flash')
        output = self.root / 'build/flash'
        project = ET.parse(output / 'stage3_flash.prj').getroot()
        self.assertEqual(project.findtext('TOP_MODULE/MODULE'), 'stage3_flash_top')
        sources = [Path(item.attrib['Path']) for item in
                   project.findall('Source_Files/Verilog/File')]
        self.assertIn(self.root / 'rtl/stage3/stage3_flash_read.v', sources)
        self.assertIn(self.root / 'rtl/stage3/stage3_flash_writer.v', sources)
        self.assertIn(self.root / 'rtl/stage3/stage3_debug_top.v', sources)
        self.assertIn(output / 'VexRiscvDebug_hw.v', sources)
        self.assertEqual(self.cpu.read_bytes(), original_cpu)
        self.assertEqual(Path(project.find('Source_Files/SDC_FILE/File').attrib['Path']),
                         self.root / 'constraints/debug.sdc')
        self.assertIn('// Flash ROM initialization',
                      (output / 'stage3_memory_hw.v').read_text())

    def test_rtos_project_preserves_uart_debug_and_firmware(self):
        uart_project = self.stage3 / 'stage3_uart.prj'
        uart_project.write_text('UART sentinel', encoding='ascii')
        debug_project = self.root / 'build/debug/stage3_debug.prj'
        debug_project.parent.mkdir(parents=True)
        debug_project.write_text('JTAG sentinel', encoding='ascii')
        output = self.root / 'build/rtos'
        output.mkdir(parents=True)
        (output / 'freertos.bin').write_bytes(b'Firmware sentinel')
        self.cpu.write_text('module VexRiscvRtos;\nendmodule\n', encoding='ascii')
        original = self.cpu.read_bytes()
        self.generate('stage3_rtos')
        project = ET.parse(output / 'stage3_rtos.prj').getroot()
        self.assertEqual(project.findtext('TOP_MODULE/MODULE'), 'stage3_rtos_top')
        sources = [Path(item.attrib['Path']) for item in project.findall('Source_Files/Verilog/File')]
        self.assertIn(output / 'VexRiscvRtos_hw.v', sources)
        for name in ('clint', 'plic', 'event'):
            self.assertIn(self.root / f'rtl/stage3/rtos_{name}.v', sources)
        self.assertEqual(self.cpu.read_bytes(), original)
        self.assertTrue((output / 'VexRiscvRtos_hw.v').read_text().startswith('`define SYNTHESIS\n'))
        self.assertEqual(uart_project.read_text(), 'UART sentinel')
        self.assertEqual(debug_project.read_text(), 'JTAG sentinel')
        self.assertEqual((output / 'freertos.bin').read_bytes(), b'Firmware sentinel')
        self.assertIn('// Test ROM initialization', (output / 'stage3_memory_hw.v').read_text())
        self.assertEqual(Path(project.find('Source_Files/SDC_FILE/File').attrib['Path']),
                         self.root / 'constraints/uart.sdc')

    def test_unified_project_contains_one_cpu_and_all_three_capabilities(self):
        self.cpu.write_text('module VexRiscvUnified;\nendmodule\n', encoding='ascii')
        original = self.cpu.read_bytes()
        self.generate('stage3_unified')
        output = self.root / 'build/unified'
        project = ET.parse(output / 'stage3_unified.prj').getroot()
        self.assertEqual(project.findtext('TOP_MODULE/MODULE'), 'stage3_unified_top')
        sources = [Path(item.attrib['Path']) for item in
                   project.findall('Source_Files/Verilog/File')]
        self.assertIn(output / 'VexRiscvUnified_hw.v', sources)
        self.assertIn(self.root / 'rtl/stage3/stage3_unified_top.v', sources)
        for name in ('clint', 'plic', 'event'):
            self.assertIn(self.root / f'rtl/stage3/rtos_{name}.v', sources)
        for name in ('read', 'writer'):
            self.assertIn(self.root / f'rtl/stage3/stage3_flash_{name}.v', sources)
        self.assertNotIn(self.root / 'rtl/stage3/stage3_debug_top.v', sources)
        self.assertNotIn(self.root / 'rtl/stage3/stage3_rtos_top.v', sources)
        self.assertIn('// Flash ROM initialization',
                      (output / 'stage3_memory_hw.v').read_text())
        self.assertEqual(self.cpu.read_bytes(), original)
        self.assertEqual(Path(project.find('Source_Files/SDC_FILE/File').attrib['Path']),
                         self.root / 'constraints/debug.sdc')

    def test_unified_config_flash_scripts_use_the_unified_bitstream_and_guard_writes(self):
        program = (prepare.ROOT / 'script/program_unified_flash_fpga.tcl').read_text()
        verify = (prepare.ROOT / 'script/verify_unified_flash_fpga.tcl').read_text()
        bit_path = 'build unified stage3_unified.bit'
        self.assertIn(bit_path, program)
        self.assertIn(bit_path, verify)
        self.assertLess(program.index('SOC_CONFIRM_UNIFIED_CONFIG_FLASH'),
                        program.index('download -mode program_spi'))
        self.assertIn('PROGRAM_UNIFIED_CONFIG_FLASH', program)
        self.assertIn('download -mode verify_spi', verify)
        self.assertNotIn('program_spi', verify)

    def test_unified_live_debug_checks_xip_and_restores_cpu_without_memory_writes(self):
        script = (prepare.ROOT / 'script/openocd/validate-unified-live-debug.tcl').read_text()
        self.assertIn('read_memory 0x30050000', script)
        self.assertIn('bp 0x30050768 4 hw', script)
        self.assertIn('step', script)
        self.assertIn('catch {rbp 0x30050768}', script)
        self.assertIn('catch {resume}', script)
        for forbidden in ('write_memory', 'load_image', 'flash write',
                          'program ', 'set_reg', 'reset run'):
            self.assertNotIn(forbidden, script)

    def test_unified_identity_probe_only_reads_required_peripherals(self):
        probe = (prepare.ROOT / 'script/openocd/probe-unified-identity.tcl').read_text()
        for address in ('0x0200bffc', '0x0c000000', '0x40002000',
                        '0x4000400c', '0x30050000'):
            self.assertIn(address, probe)
        self.assertIn('UNIFIED_IDENTITY_OK', probe)
        self.assertIn('catch {resume}', probe)
        self.assertNotIn('write_memory', probe)
        self.assertNotIn('reset run', probe)


if __name__ == '__main__':
    unittest.main()
