"""Generate TD project inputs from sources, never from a previous TD run."""
import argparse
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def prepare_uart(output):
    uart = (ROOT / 'rtl/common/uart_wb.v').read_text()
    needle = "if (i_reset) begin\n        o_wb_ack <= 1'b0;"
    if needle not in uart:
        raise ValueError('UART reset block changed; inspect before patching')
    uart = uart.replace(needle, needle + '\n        rx_fifo_r_stb <= 0;'
                        '\n        tx_fifo_w_stb <= 0;\n        o_wb_dat <= 0;')
    uart = uart.replace("rx_fifo_r_stb <= 1'b1;", "rx_fifo_r_stb <= !i_wb_we && !rx_fifo_empty;")
    (output / 'uart_wb_stage2.v').write_text(uart, encoding='ascii')
    for name in ('rx', 'tx'):
        uart = (ROOT / f'rtl/common/uart_{name}.v').read_text()
        uart = uart.replace(f'module uart_{name} (', f'module uart_{name} #(parameter DATA_WIDTH = 16) (')
        uart = uart.replace('    parameter DATA_WIDTH = 16;', '')
        if name == 'rx':
            uart = uart.replace('    reg [1:0] state = s_IDLE;', '    reg [1:0] state;')
            uart = uart.replace('        s_STOP = 2;', '        s_STOP = 2;\n    initial state = s_IDLE;')
        (output / f'uart_{name}_stage2.v').write_text(uart, encoding='ascii')
    return [output / f'uart_{name}_stage2.v' for name in ('rx', 'tx', 'wb')]


def write_project(path, name, top, sources, constraint='uart'):
    project = ET.Element('Project', Version='3', Minor='2')
    for key, value in [('TD_Version', '5.6.119222'), ('UCode', '00000000'), ('Name', name)]:
        ET.SubElement(project, key).text = value
    hardware = ET.SubElement(project, 'HardWare')
    ET.SubElement(hardware, 'Family').text = 'EF2'
    ET.SubElement(hardware, 'Device').text = 'EF2L45LG144B'
    ET.SubElement(hardware, 'Speed')
    groups = ET.SubElement(project, 'Source_Files')
    for kind, paths, owner in [('Verilog', sources, 'design_1'),
                                ('ADC_FILE', [ROOT / f'constraints/{constraint}.adc'], 'constraint_1'),
                                ('SDC_FILE', [ROOT / f'constraints/{constraint}.sdc'], 'constraint_1')]:
        group = ET.SubElement(groups, kind)
        for order, source in enumerate(paths, 1):
            if not source.is_file():
                raise FileNotFoundError(source)
            item = ET.SubElement(group, 'File', Path=source.resolve().as_posix())
            info = ET.SubElement(item, 'FileInfo')
            for key, value in [('UsedInSyn', 'true'), ('UsedInP&R', 'true'),
                               ('BelongTo', owner), ('CompileOrder', str(order))]:
                ET.SubElement(info, 'Attr', Name=key, Val=value)
    sets = ET.SubElement(project, 'FileSets')
    ET.SubElement(sets, 'FileSet', Name='design_1', Type='DesignFiles')
    ET.SubElement(sets, 'FileSet', Name='constraint_1', Type='ConstrainFiles')
    module = ET.SubElement(project, 'TOP_MODULE')
    ET.SubElement(module, 'LABEL')
    ET.SubElement(module, 'MODULE').text = top
    ET.SubElement(module, 'CREATEINDEX').text = 'user'
    for key in ('Property', 'Device_Settings', 'Configurations'):
        ET.SubElement(project, key)
    ET.indent(project, space='  ')
    ET.ElementTree(project).write(path, encoding='UTF-8', xml_declaration=True)
    print(f'Prepared {path}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('variant', choices=('stage1', 'stage2_uart', 'stage2_jtag', 'stage3_uart', 'stage3_debug'))
    parser.add_argument('--cpu', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    stage = args.variant.split('_')[0]
    debug = args.variant == 'stage3_debug'
    output = args.output or ROOT / 'build' / ('debug' if debug else stage)
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if stage == 'stage1':
        image = output / 'firmware/soc_fw.hex'
        if not image.exists():
            raise FileNotFoundError('Run build_stage1_firmware.ps1 first')
        top = (ROOT / 'rtl/stage1/design_top_wrapper.v').read_text()
        top = top.replace('../firmware/soc_fw.hex', image.as_posix())
        top_path = output / 'design_top_wrapper.v'
        top_path.write_text(top, encoding='ascii')
        sources = [top_path] + [ROOT / 'rtl/stage1' / name for name in
                               ('soc_wb_intercon.v', 'VexRiscv.v', 'wb_ram.v')]
        sources += [ROOT / 'rtl/common' / name for name in
                    ('jtag_wb_loader.v', 'fifo.v', 'uart_rx.v', 'uart_tx.v', 'uart_wb.v')]
        sources.append(ROOT / 'rtl/ip/sys_pll.v')
        write_project(output / 'stage1.prj', 'stage1', 'design_top_wrapper', sources)
        return
    if not args.cpu or not args.cpu.is_file():
        parser.error('Supply --cpu with the full VexRiscv.v (VEXRISCV_SOURCE)')
    uart = prepare_uart(output)
    if stage == 'stage2':
        image = output / 'bootrom.hex'
        if not image.is_file():
            raise FileNotFoundError('Run build_stage2_firmware.ps1 first')
        top = (ROOT / 'rtl/stage2/stage2_top.v').read_text()
        top = top.replace('../build/bootrom.hex', image.as_posix())
        top_path = output / 'stage2_top.v'
        top_path.write_text(top, encoding='ascii')
        sources = [top_path, args.cpu, ROOT / 'rtl/stage2/stage2_memory.v']
        top_name = 'stage2_jtag_top' if args.variant.endswith('jtag') else 'stage2_top'
        if args.variant.endswith('jtag'):
            sources.append(ROOT / 'rtl/common/jtag_wb_loader.v')
    else:
        init_dir = ROOT / 'build/stage3' if debug else output
        init = (init_dir / 'bootrom_init.vh').read_text()
        memory = (ROOT / 'rtl/stage3/stage3_memory.v').read_text()
        memory = memory.replace('`include "bootrom_init.vh"', init)
        memory_path = output / 'stage3_memory_hw.v'
        memory_path.write_text(memory, encoding='ascii')
        top_name = 'stage3_debug_top' if debug else 'stage3_top'
        cpu_path = args.cpu
        if debug:
            # TD does not predefine SYNTHESIS. Exclude Spinal's simulation-only
            # random power-up values; JTAG still resets its TAP via TMS.
            cpu_path = output / 'VexRiscvDebug_hw.v'
            cpu_path.write_text('`define SYNTHESIS\n' + args.cpu.read_text()
                                + '\n`undef SYNTHESIS\n', encoding='ascii')
        sources = [ROOT / f'rtl/stage3/{top_name}.v', cpu_path, memory_path]
    sources += [ROOT / 'rtl/common/fifo.v', *uart, ROOT / 'rtl/ip/sys_pll.v']
    write_project(output / f'{args.variant}.prj', args.variant, top_name, sources,
                  constraint='debug' if debug else 'uart')


if __name__ == '__main__':
    main()
