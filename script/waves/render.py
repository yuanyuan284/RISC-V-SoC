"""Render annotated timing views from the selected Stage 3 VCD recordings."""

from bisect import bisect_right
from pathlib import Path
import argparse

import matplotlib

matplotlib.use('Agg')
import matplotlib.pyplot as plt
from vcdvcd import VCDVCD


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'docs' / 'waveforms'
FLASH_READ = ROOT / 'build' / 'waves' / 'flash_read.vcd'
FLASH_SOC = ROOT / 'build' / 'flash' / 'flash_soc.vcd'
INTERRUPTS = ROOT / 'build' / 'waves' / 'rtos_interrupts.vcd'


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


def main():
    global OUTPUT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=OUTPUT)
    args = parser.parse_args()
    OUTPUT = args.output
    OUTPUT.mkdir(parents=True, exist_ok=True)
    plot_flash_read()
    plot_flash_boot()
    plot_cache_hit()
    plot_uart_byte()
    plot_interrupts()
    for path in sorted(OUTPUT.glob('*.png')):
        print(f'{path}: {path.stat().st_size} bytes')


if __name__ == '__main__':
    main()
