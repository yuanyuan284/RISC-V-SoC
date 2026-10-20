"""Render annotated timing views from the selected Stage 3 VCD recordings."""

from bisect import bisect_right
from pathlib import Path
import argparse
import csv

import matplotlib

matplotlib.use('Agg')
import matplotlib.pyplot as plt
from vcdvcd import VCDVCD


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'docs' / 'waveforms'
FLASH_READ = ROOT / 'build' / 'waves' / 'flash_read.vcd'
FLASH_SOC = ROOT / 'build' / 'flash' / 'flash_soc.vcd'
INTERRUPTS = ROOT / 'build' / 'rtos' / 'rtos_interrupts.vcd'
MEMORY = ROOT / 'build' / 'stage3' / 'stage3_memory.vcd'
UART = ROOT / 'build' / 'stage3' / 'stage3_uart.vcd'
JTAG = ROOT / 'build' / 'flash' / 'flash_jtag.vcd'
DEBUG_REMOTE = ROOT / 'build' / 'stage3' / 'debug_remote.vcd'
DEBUG_UART = ROOT / 'build' / 'stage3' / 'debug_uart.vcd'
RTOS_EVENTS = ROOT / 'build' / 'rtos' / 'rtos_events.csv'


def load(path: Path, signals: list[str]) -> VCDVCD:
    if not path.is_file():
        raise FileNotFoundError(f'Missing VCD: {path}')
    wave = VCDVCD(str(path), signals=signals)
    if wave.timescale['unit'] != 'ps' or wave.timescale['magnitude'] != 1:
        raise ValueError(f'Expected 1 ps VCD timescale: {path}')
    missing = set(signals) - set(wave.signals)
    if missing:
        raise ValueError(f'Missing VCD signals in {path}: {sorted(missing)}')
    return wave


def window(wave: VCDVCD, signal: str, start: int, stop: int):
    events = wave[signal].tv
    times = [t for t, _ in events]
    left = max(0, bisect_right(times, start) - 1)
    right = bisect_right(times, stop)
    points = [(start, events[left][1])]
    points += [(t, value) for t, value in events[left + 1:right] if t > start]
    points.append((stop, points[-1][1]))
    return points


def integers(wave: VCDVCD, signal: str, start: int, stop: int, scale: int):
    points = window(wave, signal, start, stop)
    values = [int(value, 2) if all(c in '01' for c in value) else float('nan')
              for _, value in points]
    return [t / scale for t, _ in points], values


def digital(ax, wave, signal, start, stop, row, label, color, scale):
    x, values = integers(wave, signal, start, stop, scale)
    ax.step(x, [row + 0.68 * value for value in values], where='post',
            color=color, linewidth=1.6)
    ax.hlines(row, start / scale, stop / scale, color='#d5dce0', linewidth=0.7)
    ax.text(start / scale - (stop - start) / scale * 0.012, row + 0.3,
            label, va='center', ha='right', fontsize=10)


def plot_flash_read():
    base = 'tb_flash_read.'
    names = ['cycle', 'strobe', 'spi_cs_n', 'spi_sck', 'spi_mosi',
             'spi_miso', 'ack', 'dut.state[1:0]', 'read_count[31:0]']
    wave = load(FLASH_READ, [base + name for name in names])
    start, stop, scale = 0, 5_500_000, 1_000_000
    fig, (ax, state) = plt.subplots(2, 1, figsize=(13, 7), sharex=True,
                                     gridspec_kw={'height_ratios': [4, 1]})
    rows = [('cycle', 'Wishbone CYC', '#147d83'),
            ('strobe', 'Wishbone STB', '#147d83'),
            ('spi_cs_n', 'SPI CS#', '#bb5845'),
            ('spi_sck', 'SPI SCK', '#9a7020'),
            ('spi_mosi', 'MOSI', '#286eb3'),
            ('spi_miso', 'MISO', '#6860ad'),
            ('ack', 'Wishbone ACK', '#1a8a59')]
    for row, (name, label, color) in enumerate(rows[::-1]):
        digital(ax, wave, base + name, start, stop, row, label, color, scale)
    ax.set_ylim(-0.25, len(rows) + 0.15)
    ax.set_yticks([])
    ax.set_title('Flash read: Wishbone request -> SPI 03h -> 32-bit response',
                 fontsize=14, loc='left')
    ax.axvspan(0.18, 2.74, color='#dcecf6', alpha=0.5)
    ax.axvspan(2.74, 5.30, color='#f9e8d5', alpha=0.5)
    ax.text(0.5, 6.8, '8-bit command + 24-bit address', fontsize=10)
    ax.text(3.0, 6.8, '32-bit flash data', fontsize=10)
    x, values = integers(wave, base + 'dut.state[1:0]', start, stop, scale)
    state.step(x, values, where='post', color='#444e5a')
    state.set_yticks([0, 1, 2, 3], ['IDLE', 'SEND', 'RECEIVE', 'RESPOND'])
    state.set_xlabel('Time (us)')
    state.grid(axis='x', alpha=0.25)
    fig.tight_layout()
    fig.savefig(OUTPUT / 'flash_read.png', dpi=160)
    plt.close(fig)


def plot_flash_boot():
    base = 'tb_flash_soc.'
    signals = ['power_reset', 'board_reset', 'wave_phase[2:0]',
               'count[31:0]', 'ram_iterations[31:0]',
               'dut.flash_read_count[31:0]', 'tx']
    wave = load(FLASH_SOC, [base + name for name in signals])
    start, stop, scale = 0, 6_450_000_000, 1_000_000_000
    fig, axes = plt.subplots(4, 1, figsize=(13, 9), sharex=True)
    x, values = integers(wave, base + 'power_reset', start, stop, scale)
    axes[0].step(x, values, where='post', color='#bb5845', label='Power reset')
    axes[0].set_ylabel('Reset')
    for ax, name, label, color in (
            (axes[1], 'dut.flash_read_count[31:0]', 'SPI reads', '#286eb3'),
            (axes[2], 'count[31:0]', 'UART bytes', '#147d83'),
            (axes[3], 'ram_iterations[31:0]', 'RAM loop count', '#1a8a59')):
        x, values = integers(wave, base + name, start, stop, scale)
        ax.step(x, values, where='post', color=color, linewidth=1.6)
        ax.set_ylabel(label)
        ax.grid(axis='x', alpha=0.25)
    for ax in axes:
        ax.axvline(5.78366, color='#444e5a', linestyle='--', linewidth=1)
    axes[0].set_title('Flash XIP boot: image check, UART output, running loop',
                      fontsize=14, loc='left')
    axes[0].text(0.16, 0.4, 'Reset released', fontsize=10)
    axes[2].text(0.3, 22, 'BOOT FLASH / HELLO,YUAN! bytes', fontsize=10)
    axes[3].text(4.7, 650, 'XIP loop begins', fontsize=10)
    axes[-1].set_xlabel('Time (ms)')
    fig.tight_layout()
    fig.savefig(OUTPUT / 'flash_boot.png', dpi=160)
    plt.close(fig)


def plot_flash_fallback():
    base = 'tb_flash_soc.'
    names = ['wave_phase[2:0]', 'board_reset', 'count[31:0]',
             'dut.flash_read_count[31:0]']
    wave = load(FLASH_SOC, [base + name for name in names])
    start, stop, scale = 6_400_000_000, 13_338_800_000, 1_000_000_000
    fig, axes = plt.subplots(3, 1, figsize=(13, 7), sharex=True)
    for ax, name, label, color in (
            (axes[0], 'wave_phase[2:0]', 'Test phase', '#6860ad'),
            (axes[1], 'dut.flash_read_count[31:0]', 'SPI read count', '#286eb3'),
            (axes[2], 'count[31:0]', 'UART bytes decoded', '#147d83')):
        x, values = integers(wave, base + name, start, stop, scale)
        ax.step(x, values, where='post', color=color)
        ax.set_ylabel(label)
        ax.grid(axis='x', alpha=0.2)
    axes[0].set(yticks=[2, 3, 4],
                yticklabels=['Cached loop', 'Bad CRC', 'Invalid header'])
    axes[0].set_title('Flash boot fallback: failed XIP images return to UART loader',
                      fontsize=14, loc='left')
    axes[2].set_xlabel('Simulation time (ms)')
    for ax in axes:
        for time_ms, label in ((6.45066, 'CRC-corrupted reboot'),
                               (12.0168, 'Header-invalid reboot')):
            ax.axvline(time_ms, color='#bb5845', linestyle='--', linewidth=0.8)
    fig.tight_layout()
    fig.savefig(OUTPUT / 'flash_fallback.png', dpi=160)
    plt.close(fig)


def plot_cache_hit():
    base = 'tb_flash_soc.'
    names = ['ram_iterations[31:0]', 'dut.flash_read_count[31:0]',
             'ram_spi_reads[31:0]']
    wave = load(FLASH_SOC, [base + name for name in names])
    start, stop, scale = 5_800_000_000, 6_430_000_000, 1_000_000_000
    fig, ax = plt.subplots(figsize=(13, 5))
    x, iterations = integers(wave, base + names[0], start, stop, scale)
    ax.step(x, iterations, where='post', color='#1a8a59',
            label='RAM loop iterations')
    ax.set_ylabel('Loop iterations')
    ax.set_ylim(0, 1000)
    ax.set_xlabel('Time (ms)')
    other = ax.twinx()
    for name, label, color, style in (
            (names[1], 'SPI transactions', '#286eb3', '-'),
            (names[2], 'Application-observed SPI reads', '#bb5845', '--')):
        x, values = integers(wave, base + name, start, stop, scale)
        other.step(x, values, where='post', color=color, linestyle=style,
                   label=label)
    other.set_ylabel('SPI reads')
    other.set_ylim(95, 120)
    ax.set_title('1-way I-cache: software keeps looping while SPI reads stay flat',
                 fontsize=14, loc='left')
    ax.grid(axis='x', alpha=0.25)
    ax.legend(loc='upper left')
    other.legend(loc='lower right')
    fig.tight_layout()
    fig.savefig(OUTPUT / 'cache_hit.png', dpi=160)
    plt.close(fig)


def plot_uart_byte():
    signal = 'tb_flash_soc.tx'
    wave = load(FLASH_SOC, [signal])
    bit_ps = 8_680_000
    edge_ps = 4_264_060_000
    start, stop, scale = edge_ps - 4_000_000, edge_ps + 10 * bit_ps + 4_000_000, 1_000_000
    fig, ax = plt.subplots(figsize=(13, 3.5))
    x, values = integers(wave, signal, start, stop, scale)
    ax.step(x, values, where='post', color='#147d83', linewidth=2)
    labels = ['Start', 'D0=0', 'D1=1', 'D2=0', 'D3=0',
              'D4=0', 'D5=0', 'D6=1', 'D7=0', 'Stop']
    for bit, label in enumerate(labels):
        left = (edge_ps + bit * bit_ps) / scale
        ax.axvline(left, color='#c5cdd1', linewidth=0.8, linestyle='--')
        ax.text(left + bit_ps / scale / 2, 1.20, label,
                ha='center', va='center', fontsize=9)
    ax.axvline((edge_ps + 10 * bit_ps) / scale, color='#c5cdd1',
               linewidth=0.8, linestyle='--')
    ax.set(xlim=(start / scale, stop / scale), ylim=(-0.2, 1.5),
           yticks=[0, 1], ylabel='UART TX', xlabel='Time (us)')
    ax.set_title('First UART character: "B" = 0x42, 115200 8N1, LSB first',
                 fontsize=14, loc='left')
    ax.grid(axis='x', alpha=0.2)
    fig.tight_layout()
    fig.savefig(OUTPUT / 'uart_first_byte.png', dpi=160)
    plt.close(fig)


def plot_interrupts():
    base = 'tb_rtos_interrupts.'
    names = ['reset', 'cycle', 'we', 'ca', 'pa', 'si', 'ti', 'ei',
             'sources[2:1]', 'plic.pending[2:1]', 'plic.threshold[1:0]']
    wave = load(INTERRUPTS, [base + name for name in names])
    start, stop, scale = 0, 4_461_000, 1_000_000
    fig, (ax, state) = plt.subplots(2, 1, figsize=(13, 8), sharex=True,
                                     gridspec_kw={'height_ratios': [4, 1]})
    rows = [('reset', 'Reset', '#bb5845'),
            ('cycle', 'MMIO CYC', '#147d83'),
            ('we', 'MMIO write', '#286eb3'),
            ('ca', 'CLINT ACK', '#1a8a59'),
            ('pa', 'PLIC ACK', '#1a8a59'),
            ('si', 'Software IRQ', '#9a7020'),
            ('ti', 'Timer IRQ', '#bb5845'),
            ('ei', 'External IRQ', '#6860ad')]
    for row, (name, label, color) in enumerate(rows[::-1]):
        digital(ax, wave, base + name, start, stop, row, label, color, scale)
    ax.set_ylim(-0.25, len(rows) + 0.15)
    ax.set_yticks([])
    ax.set_title('CLINT + PLIC: writes, acknowledgments and three IRQ lines',
                 fontsize=14, loc='left')
    for time_us, label in ((0.22, 'MSIP'), (0.70, 'MTIP'),
                           (2.62, 'PLIC')):
        ax.axvline(time_us, color='#66747d', linewidth=0.8,
                   linestyle=':', alpha=0.8)
        ax.text(time_us + 0.03, 7.85, label, fontsize=9,
                rotation=90, va='top')
    for name, label, color in (
            ('sources[2:1]', 'Sources', '#286eb3'),
            ('plic.pending[2:1]', 'Pending', '#bb5845'),
            ('plic.threshold[1:0]', 'Threshold', '#1a8a59')):
        x, values = integers(wave, base + name, start, stop, scale)
        state.step(x, values, where='post', color=color, label=label)
    state.set_ylabel('PLIC state')
    state.set_xlabel('Time (us)')
    state.legend(loc='upper right', ncol=3)
    state.grid(axis='x', alpha=0.25)
    fig.tight_layout()
    fig.savefig(OUTPUT / 'rtos_interrupts.png', dpi=160)
    plt.close(fig)


def plot_memory():
    base = 'tb_stage3_memory.'
    names = ['rom_cycle', 'rom_ack', 'rom_address[10:0]', 'rom_data[31:0]',
             'cycle', 'we', 'ack', 'address[13:0]',
             'write_data[31:0]', 'data[31:0]']
    wave = load(MEMORY, [base + name for name in names])
    views = [
        ('BootROM: first four synchronous reads', 120_000, 480_000,
         [('rom_cycle', 'ROM CYC'), ('rom_ack', 'ROM ACK')],
         'rom_address[10:0]', 'rom_data[31:0]'),
        ('RAM: first four word writes', 163_980_000, 164_300_000,
         [('cycle', 'RAM CYC'), ('we', 'Write enable'), ('ack', 'RAM ACK')],
         'address[13:0]', 'write_data[31:0]'),
        ('RAM: same words read back', 1_474_700_000, 1_475_020_000,
         [('cycle', 'RAM CYC'), ('we', 'Write enable'), ('ack', 'RAM ACK')],
         'address[13:0]', 'data[31:0]'),
    ]
    fig, axes = plt.subplots(3, 1, figsize=(13, 9))
    for ax, (title, start, stop, rows, address, data) in zip(axes, views):
        for row, (name, label) in enumerate(rows[::-1]):
            digital(ax, wave, base + name, start, stop, row, label,
                    '#147d83' if name.endswith('cycle') else '#286eb3', 1_000)
        ax.set(ylim=(-0.9, len(rows) + 0.1), yticks=[],
               xlabel='Time (ns)', title=title)
        ax.grid(axis='x', alpha=0.2)
        cycle_name = 'rom_cycle' if address.startswith('rom_') else 'cycle'
        first_cycle = next(t for t, value in wave[base + cycle_name].tv
                           if start <= t <= stop and value == '1')
        first_address = window(wave, base + address, first_cycle,
                               first_cycle + 1)[0][1]
        addr_events = [(first_cycle, first_address)]
        addr_events += [(t, value) for t, value in wave[base + address].tv
                        if first_cycle < t <= stop and all(bit in '01' for bit in value)]
        for t, value in addr_events[:4]:
            read_at = t + 20_000
            data_points = window(wave, base + data, read_at, read_at + 1)
            bits = data_points[0][1]
            if all(bit in '01' for bit in bits):
                label = f'{int(value, 2)}: {int(bits, 2):08x}'
                ax.text(t / 1_000 + 2, -0.55, label, fontsize=8,
                        ha='left', va='center')
    fig.suptitle('8 KiB BootROM and 64 KiB RAM: request, ACK, data',
                 fontsize=14, x=0.13, ha='left')
    fig.tight_layout()
    fig.savefig(OUTPUT / 'memory_access.png', dpi=160)
    plt.close(fig)


def plot_stage3_uart():
    base = 'tb_stage3_uart.'
    names = ['rx', 'tx']
    wave = load(UART, [base + name for name in names])
    edge = 1_315_000_000
    bit = 8_680_000
    start, stop, scale = edge - 5_000_000, edge + 12 * bit, 1_000_000
    fig, ax = plt.subplots(figsize=(13, 4))
    for row, (name, label, color) in enumerate((
            ('tx', 'FPGA TX', '#286eb3'),
            ('rx', 'Host TX -> FPGA RX', '#147d83'))):
        digital(ax, wave, base + name, start, stop, row, label, color, scale)
    labels = ['Start', 'D0=0', 'D1=1', 'D2=0', 'D3=0',
              'D4=1', 'D5=0', 'D6=1', 'D7=0', 'Stop']
    for index, label in enumerate(labels):
        left = (edge + index * bit) / scale
        ax.axvline(left, color='#a7b5bc', linewidth=0.7, linestyle='--')
        ax.text(left + bit / scale / 2, 2.15, label,
                ha='center', va='bottom', fontsize=8)
    ax.set(xlim=(start / scale, stop / scale), ylim=(-0.25, 2.6),
           yticks=[], xlabel='Time (us)')
    ax.set_title('Stage 3 UART: first received header byte "R" (0x52), 115200 8N1',
                 fontsize=14, loc='left')
    ax.grid(axis='x', alpha=0.2)
    fig.tight_layout()
    fig.savefig(OUTPUT / 'stage3_uart.png', dpi=160)
    plt.close(fig)


def plot_clock_reset():
    base = 'tb_stage3_uart.'
    names = ['clk_ref', 'dut.clk', 'dut.reset']
    wave = load(UART, [base + name for name in names])
    start, stop, scale = 0, 2_500_000, 1_000_000
    fig, ax = plt.subplots(figsize=(13, 4.5))
    for row, name, label, color in (
            (2, 'clk_ref', '10 MHz reference', '#286eb3'),
            (1, 'dut.clk', '25 MHz system', '#147d83'),
            (0, 'dut.reset', 'CPU reset', '#bb5845')):
        digital(ax, wave, base + name, start, stop, row, label, color, scale)
    ax.axvline(1.5, color='#66747d', linestyle='--', linewidth=0.9)
    ax.text(1.52, 2.82, 'Reset released', fontsize=9, va='top')
    ax.set(ylim=(-0.2, 3.05), yticks=[], xlabel='Simulation time (us)')
    ax.set_title('Stage 3 clock and reset: 10 MHz reference, 25 MHz system',
                 fontsize=14, loc='left')
    ax.grid(axis='x', alpha=0.2)
    fig.tight_layout()
    fig.savefig(OUTPUT / 'clock_reset.png', dpi=160)
    plt.close(fig)


def plot_wishbone_decode():
    base = 'tb_stage3_uart.'
    names = ['dut.cycle', 'dut.strobe', 'dut.data_owner',
             'dut.rom_select', 'dut.ram_select', 'dut.uart_select',
             'dut.ack']
    wave = load(UART, [base + name for name in names])
    views = [
        (6_780_000, 7_220_000, 'BootROM fetch, address 0x20000000',
         'dut.rom_select', 'ROM select'),
        (8_860_000, 9_300_000, 'RAM access, address 0x8000fff4',
         'dut.ram_select', 'RAM select'),
        (12_780_000, 13_220_000, 'UART MMIO, address 0x40001000',
         'dut.uart_select', 'UART select'),
    ]
    fig, axes = plt.subplots(3, 1, figsize=(13, 9))
    for ax, (start, stop, title, select, select_label) in zip(axes, views):
        rows = [('dut.cycle', 'CYC'), ('dut.strobe', 'STB'),
                ('dut.data_owner', 'Data owner'),
                (select, select_label), ('dut.ack', 'ACK')]
        for row, (name, label) in enumerate(rows[::-1]):
            digital(ax, wave, base + name, start, stop, row, label,
                    '#1a8a59' if name.endswith('ack') else '#286eb3',
                    1_000_000)
        ax.set(ylim=(-0.2, len(rows) + 0.1), yticks=[],
               xlabel='Simulation time (us)', title=title)
        ax.grid(axis='x', alpha=0.2)
    fig.suptitle('Wishbone arbitration and address decoding',
                 fontsize=14, x=0.13, ha='left')
    fig.tight_layout()
    fig.savefig(OUTPUT / 'wishbone_decode.png', dpi=160)
    plt.close(fig)


def plot_jtag():
    base = 'tb_flash_remote.'
    tap = 'dut.cpu.debugTransportModuleJtagTap_1.'
    names = ['tck', 'tms', 'tdi', 'tdo',
             tap + 'tap_fsm_state[3:0]', tap + 'tap_instruction[4:0]']
    wave = load(JTAG, [base + name for name in names])
    start, stop, scale = 141_500_000, 159_500_000, 1_000_000
    fig, (pins, tap_ax) = plt.subplots(2, 1, figsize=(13, 7), sharex=True,
                                       gridspec_kw={'height_ratios': [4, 2]})
    for row, (name, color) in enumerate((('tdo', '#6860ad'),
                                         ('tdi', '#286eb3'),
                                         ('tms', '#bb5845'),
                                         ('tck', '#147d83'))):
        digital(pins, wave, base + name, start, stop, row,
                name.upper(), color, scale)
    pins.set(ylim=(-0.2, 4.1), yticks=[])
    pins.set_title('CPU JTAG: serial pins and TAP instruction scans',
                   fontsize=14, loc='left')
    x, values = integers(wave, base + tap + 'tap_fsm_state[3:0]',
                         start, stop, scale)
    tap_ax.step(x, values, where='post', color='#1a8a59', label='TAP state')
    tap_ax.set(yticks=[0, 1, 4, 8, 10, 11, 15], ylim=(-0.5, 16),
               ylabel='TAP state', xlabel='Time (us)')
    instruction = tap_ax.twinx()
    x, values = integers(wave, base + tap + 'tap_instruction[4:0]',
                         start, stop, scale)
    instruction.step(x, values, where='post', color='#9a7020',
                     label='Instruction')
    instruction.set(yticks=[1, 16, 31],
                    yticklabels=['01', '10', '1F'],
                    ylim=(0, 33), ylabel='JTAG IR (hex)')
    tap_ax.grid(axis='x', alpha=0.2)
    fig.tight_layout()
    fig.savefig(OUTPUT / 'jtag_tap.png', dpi=160)
    plt.close(fig)


def plot_debug_halt():
    base = 'tb_debug_remote.'
    names = ['dut.cpu.debugBus_haltReq', 'dut.cpu.debugBus_halted',
             'dut.cycle', 'dut.ram_select', 'dut.ack']
    wave = load(DEBUG_REMOTE, [base + name for name in names])
    fig, axes = plt.subplots(2, 1, figsize=(13, 7))
    views = [
        (550_000_000, 1_300_000_000, names[:2],
         'OpenOCD halt request, CPU acknowledgement, resume and second halt'),
        (623_500_000, 624_300_000, names,
         'First halt edge: zoomed CPU and Wishbone activity'),
    ]
    for ax, (start, stop, signals, title) in zip(axes, views):
        for row, name in enumerate(signals[::-1]):
            label = name.rsplit('.', 1)[-1]
            digital(ax, wave, base + name, start, stop, row, label,
                    '#147d83' if 'halt' in label else '#286eb3', 1_000_000)
        ax.set(ylim=(-0.2, len(signals) + 0.1), yticks=[],
               xlabel='Simulation time (us)', title=title)
        ax.grid(axis='x', alpha=0.2)
    for time_us, label in ((623.74, 'haltReq'), (623.98, 'halted')):
        axes[1].axvline(time_us, color='#bb5845', linestyle='--', linewidth=0.9)
        axes[1].text(time_us + 0.012, len(names) - 0.15, label,
                     rotation=90, fontsize=8, va='top')
    fig.suptitle('Independent CPU JTAG: halt and resume through the Debug Module',
                 fontsize=14, x=0.13, ha='left')
    fig.tight_layout()
    fig.savefig(OUTPUT / 'debug_halt.png', dpi=160)
    plt.close(fig)


def plot_debug_pc():
    base = 'tb_debug_remote.dut.cpu.'
    valid_name = base + 'writeBack_arbitration_isValid'
    pc_name = base + 'writeBack_PC[31:0]'
    halted_name = base + 'debugBus_halted'
    wave = load(DEBUG_REMOTE, [valid_name, pc_name, halted_name])
    valid_events = wave[valid_name].tv
    valid_times = [time for time, _ in valid_events]
    views = [(623_400_000, 624_400_000, 'First halt'),
             (1_097_100_000, 1_098_900_000, 'Resume and execute')]
    fig, axes = plt.subplots(2, 1, figsize=(13, 8))
    for ax, (start, stop, title) in zip(axes, views):
        pc_points = []
        for time, bits in wave[pc_name].tv:
            if not start <= time <= stop or set(bits) - {'0', '1'}:
                continue
            prior = bisect_right(valid_times, time) - 1
            if prior >= 0 and valid_events[prior][1] == '1':
                pc_points.append((time / 1_000_000, int(bits, 2)))
        if not pc_points:
            raise ValueError(f'No valid writeback PC in {title} window')
        ax.scatter([time for time, _ in pc_points],
                   [pc - 0x20000000 for _, pc in pc_points],
                   marker='o', s=27, color='#286eb3', label='Valid writeback PC')
        ax.set(xlim=(start / 1_000_000, stop / 1_000_000),
               ylabel='PC offset from 0x20000000',
               xlabel='Simulation time (us)', title=title)
        ax.grid(alpha=0.2)
        halted = ax.twinx()
        times, values = integers(wave, halted_name, start, stop, 1_000_000)
        halted.step(times, values, where='post', color='#bb5845',
                    linewidth=1.4, label='CPU halted')
        halted.set(ylim=(-0.15, 1.25), yticks=[0, 1], ylabel='Halted')
        if title == 'First halt':
            ax.axvline(623.98, linestyle='--', color='#666666', linewidth=0.9)
            ax.text(624.0, 0.92, 'Halt acknowledged', transform=ax.get_xaxis_transform(),
                    fontsize=9, va='top')
    fig.suptitle('CPU writeback PC: stops on halt, advances after resume',
                 fontsize=14, x=0.13, ha='left')
    fig.tight_layout()
    fig.savefig(OUTPUT / 'debug_pc.png', dpi=160)
    plt.close(fig)


def plot_debug_uart_reset():
    base = 'tb_debug_uart.'
    names = ['power_reset', 'board_reset', 'count[31:0]', 'tx']
    wave = load(DEBUG_UART, [base + name for name in names])
    stop = wave.endtime
    fig, (reset_ax, bytes_ax) = plt.subplots(2, 1, figsize=(13, 6),
                                             sharex=True)
    for row, name, label, color in (
            (1, 'power_reset', 'Power reset', '#bb5845'),
            (0, 'board_reset', 'Board reset', '#286eb3')):
        digital(reset_ax, wave, base + name, 0, stop, row, label, color,
                1_000_000_000)
    reset_ax.set(ylim=(-0.2, 2.2), yticks=[])
    x, values = integers(wave, base + 'count[31:0]', 0, stop,
                         1_000_000_000)
    bytes_ax.step(x, values, where='post', color='#147d83')
    bytes_ax.set(ylabel='Decoded UART bytes', xlabel='Simulation time (ms)')
    reset_ax.set_title('Debug CPU: BootROM banner repeats after board reset',
                       fontsize=14, loc='left')
    for ax in (reset_ax, bytes_ax):
        ax.grid(axis='x', alpha=0.2)
    fig.tight_layout()
    fig.savefig(OUTPUT / 'debug_uart_reset.png', dpi=160)
    plt.close(fig)


def read_rtos_events():
    if not RTOS_EVENTS.is_file():
        raise FileNotFoundError(f'Missing RTOS event trace: {RTOS_EVENTS}')
    with RTOS_EVENTS.open(newline='') as stream:
        rows = list(csv.DictReader(stream))
    if not rows or int(rows[-1]['time_ps']) < 70_000_000_000:
        raise ValueError('RTOS trace stops before the final validation window')
    last = rows[-1]
    if (int(last['timer_edges']) < 60 or int(last['software_edges']) != 1
            or int(last['external_edges']) < 2):
        raise ValueError('RTOS interrupt coverage is incomplete')
    return rows


def plot_rtos_system():
    rows = read_rtos_events()
    time_ms = [int(row['time_ps']) / 1_000_000_000 for row in rows]
    fig, axes = plt.subplots(3, 1, figsize=(13, 9), sharex=True)
    axes[0].step(time_ms, [int(row['timer_edges']) for row in rows],
                 where='post', label='Timer IRQs', color='#bb5845')
    lines_ax = axes[0].twinx()
    lines_ax.step(time_ms, [int(row['lines']) for row in rows],
                  where='post', label='UART lines decoded', color='#147d83')
    axes[0].set_ylabel('Timer IRQ count')
    lines_ax.set(ylim=(-0.2, 4.5), yticks=[0, 1, 2, 3, 4],
                 ylabel='UART lines')
    axes[0].legend(loc='upper left')
    lines_ax.legend(loc='center right')
    for field, label, color in (
            ('software_edges', 'Software IRQs', '#9a7020'),
            ('external_edges', 'External IRQs', '#6860ad')):
        axes[1].step(time_ms, [int(row[field]) for row in rows],
                     where='post', label=label, color=color)
    axes[1].set_ylabel('Count')
    axes[1].legend(loc='upper left')
    for offset, field, label, color in (
            (2, 'timer_irq', 'MTIP', '#bb5845'),
            (1, 'software_irq', 'MSIP', '#9a7020'),
            (0, 'external_irq', 'MEIP', '#6860ad')):
        values = [float(row[field]) if row[field] in ('0', '1')
                  else float('nan') for row in rows]
        axes[2].step(time_ms, [offset + 0.65 * value for value in values],
                     where='post', label=label, color=color)
    axes[2].set(ylim=(-0.2, 2.9), yticks=[0.3, 1.3, 2.3],
                yticklabels=['MEIP', 'MSIP', 'MTIP'],
                xlabel='Simulation time (ms)')
    axes[0].set_title('FreeRTOS SoC: decoded output and interrupt activity',
                      fontsize=14, loc='left')
    for ax in axes:
        ax.grid(axis='x', alpha=0.25)
    fig.tight_layout()
    fig.savefig(OUTPUT / 'rtos_system.png', dpi=160)
    plt.close(fig)


def plot_rtos_irq_detail():
    rows = read_rtos_events()
    choices = [('timer_irq', 'Timer interrupt (MTIP)', 0),
               ('software_irq', 'Software interrupt (MSIP)', 0),
               ('external_irq', 'UART external interrupt (MEIP)', 0)]
    fig, axes = plt.subplots(3, 1, figsize=(13, 8))
    for ax, (field, title, occurrence) in zip(axes, choices):
        rising = []
        previous = rows[0][field]
        for row in rows[1:]:
            if row[field] == '1' and previous != '1':
                rising.append(int(row['time_ps']))
            previous = row[field]
        if len(rising) <= occurrence:
            raise ValueError(f'Missing {title} edge #{occurrence + 1}')
        edge = rising[occurrence]
        lookback_us = 100 if field == 'external_irq' else 50
        start, stop = edge - lookback_us * 1_000_000, edge + 150_000_000
        selected = [row for row in rows if start <= int(row['time_ps']) <= stop]
        before = [row for row in rows if int(row['time_ps']) < start]
        if before:
            selected.insert(0, dict(before[-1], time_ps=str(start)))
        selected.append(dict(selected[-1], time_ps=str(stop)))
        x = [(int(row['time_ps']) - edge) / 1_000_000 for row in selected]
        y = [int(row[field]) if row[field] in ('0', '1')
             else float('nan') for row in selected]
        ax.step(x, y, where='post', color='#6860ad', label=field)
        if field == 'external_irq':
            rx = [int(row['rx']) if row['rx'] in ('0', '1')
                  else float('nan') for row in selected]
            ax.step(x, [2 + value for value in rx], where='post',
                    color='#147d83', label='FPGA RX')
            ax.set(ylim=(-0.2, 3.2), yticks=[0, 1, 2, 3])
        else:
            ax.set(ylim=(-0.2, 1.2), yticks=[0, 1])
        ax.axvline(0, color='#66747d', linestyle='--', linewidth=0.9)
        ax.set(xlim=(-lookback_us, 150),
               xlabel='Time relative to IRQ rising edge (us)',
               title=f'{title}, event at {edge / 1_000_000_000:.3f} ms')
        ax.grid(axis='x', alpha=0.2)
        ax.legend(loc='upper right')
    fig.suptitle('FreeRTOS: selected interrupt edges from the full SoC run',
                 fontsize=14, x=0.13, ha='left')
    fig.tight_layout()
    fig.savefig(OUTPUT / 'rtos_irq_detail.png', dpi=160)
    plt.close(fig)


def main():
    global OUTPUT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=OUTPUT)
    args = parser.parse_args()
    OUTPUT = args.output
    OUTPUT.mkdir(parents=True, exist_ok=True)
    plot_flash_read()
    plot_flash_boot()
    plot_flash_fallback()
    plot_cache_hit()
    plot_uart_byte()
    plot_interrupts()
    plot_memory()
    plot_stage3_uart()
    plot_clock_reset()
    plot_wishbone_decode()
    plot_jtag()
    plot_debug_halt()
    plot_debug_pc()
    plot_debug_uart_reset()
    plot_rtos_system()
    plot_rtos_irq_detail()
    for path in sorted(OUTPUT.glob('*.png')):
        print(f'{path}: {path.stat().st_size} bytes')


if __name__ == '__main__':
    main()
