"""Verify ELF load layout, objcopy BIN/Intel HEX consistency and ROM INIT."""
from pathlib import Path
import hashlib
import json
import re
import struct
import subprocess

from uart_upload_stage3 import packet

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'stage3/build'
NM = Path(r'D:\risc-v\toolchain\xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf-nm.exe')


def intel_hex(path):
    memory, upper, eof = {}, 0, False
    for line in path.read_text().splitlines():
        if not line.startswith(':') or eof:
            raise ValueError('Invalid Intel HEX record or data after EOF')
        record = bytes.fromhex(line[1:])
        if len(record) != record[0] + 5 or sum(record) % 256:
            raise ValueError('Intel HEX length/checksum invalid')
        size, address, kind = record[0], int.from_bytes(record[1:3], 'big'), record[3]
        data = record[4:-1]
        if kind == 0:
            for offset, byte in enumerate(data):
                key = upper + address + offset
                if key in memory:
                    raise ValueError('Overlapping Intel HEX data')
                memory[key] = byte
        elif kind == 1:
            if size or address:
                raise ValueError('Invalid EOF')
            eof = True
        elif kind in (2, 4):
            if size != 2 or address:
                raise ValueError('Invalid extended address')
            upper = int.from_bytes(data, 'big') << (4 if kind == 2 else 16)
        elif kind in (3, 5):
            if size != 4:
                raise ValueError('Invalid entry record')
        else:
            raise ValueError(f'Unsupported Intel HEX record type {kind}')
    if not eof:
        raise ValueError('Missing Intel HEX EOF')
    return memory


def verify_image(name, base, limit):
    elf = (OUT / f'{name}.elf').read_bytes()
    assert elf[:7] == b'\x7fELF\x01\x01\x01', 'Expected ELF32 little endian'
    header = struct.unpack_from('<16sHHIIIIIHHHHHH', elf)
    assert header[1:3] == (2, 243) and header[4] == base, 'Wrong ELF machine/type/entry'
    load = {}
    for i in range(header[10]):
        segment = struct.unpack_from('<8I', elf, header[5] + i * header[9])
        kind, offset, vaddr, paddr, filesz, memsz, flags, align = segment
        if kind != 1:
            continue
        assert vaddr == paddr and base <= paddr < base + limit
        assert filesz <= memsz and paddr + memsz <= base + limit
        assert offset + filesz <= len(elf)
        for j, byte in enumerate(elf[offset:offset + filesz]):
            assert paddr + j not in load, 'Overlapping load segments'
            load[paddr + j] = byte
    assert load and min(load) == base
    binary = bytes(load.get(i, 0) for i in range(base, max(load) + 1))
    assert binary == (OUT / f'{name}.bin').read_bytes(), 'BIN differs from ELF load bytes'
    assert intel_hex(OUT / f'{name}.hex') == load, 'Intel HEX differs from ELF load bytes'
    words = b''.join(struct.pack('<I', int(line, 16))
                     for line in (OUT / f'{name}.words.hex').read_text().splitlines())
    assert words[:len(binary)] == binary and not any(words[len(binary):])
    symbols = {}
    for line in subprocess.check_output([str(NM), str(OUT / f'{name}.elf')], text=True).splitlines():
        fields = line.split()
        if len(fields) == 3:
            symbols[fields[2]] = int(fields[0], 16)
    if name != 'bootrom':
        assert symbols['_bss_start'] >= base + len(binary)
        assert base <= symbols['_bss_start'] <= symbols['_bss_end'] <= symbols['_heap_start']
        assert symbols['_heap_start'] + 4096 <= symbols['_heap_end'] <= symbols['_stack_bottom']
        assert symbols['_stack_bottom'] == 0x8000f000 and symbols['_stack_top'] == 0x80010000
        assert all(s in symbols for s in ('printf', 'snprintf', '_printf_float', '_write', '_sbrk'))
        frame = bytes(int(line, 16) for line in (OUT / f'{name}.frame.hex').read_text().splitlines())
        assert frame == packet(binary), 'Simulation frame differs from real UART uploader'
    return {'bin_bytes': len(binary), 'bin_sha256': hashlib.sha256(binary).hexdigest(),
            'entry': f'0x{base:08x}', 'stack_top': f"0x{symbols['_stack_top']:08x}"}


def main():
    result = {'bootrom': verify_image('bootrom', 0x20000000, 8192)}
    for name in ('app_a', 'app_b'):
        result[name] = verify_image(name, 0x80000000, 61440)
    init = (OUT / 'bootrom_init.vh').read_text()
    rom = (OUT / 'bootrom.bin').read_bytes().ljust(8192, b'\0')
    for lane, instance in ((0, 'lo'), (2, 'hi')):
        groups = re.findall(rf'defparam {instance}\.INIT_([0-9A-F]+) = ROM \? 256\'h([0-9a-f]+)', init)
        assert len(groups) == 128
        halves = b''.join(int(value, 16).to_bytes(32, 'little') for group, value in groups)
        assert halves == b''.join(rom[i+lane:i+lane+2] for i in range(0, 8192, 4))
    result['verified'] = 'ELF/BIN/Intel HEX/RTL words/physical ROM INIT/UART frames/stdio symbols'
    (OUT / 'artifact_verification.json').write_text(json.dumps(result, indent=2) + '\n', encoding='ascii')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
