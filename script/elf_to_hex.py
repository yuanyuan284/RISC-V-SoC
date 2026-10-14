"""Convert a constrained ELF32 RISC-V executable to stage-1 RAM word HEX.

Offline conversion only: this does not validate CPU instruction support or JTAG.
"""

import argparse
from pathlib import Path
import struct

from hex_to_svf import BASE, LIMIT

HEADER = struct.Struct("<16sHHIIIIIHHHHHH")
PROGRAM_HEADER = struct.Struct("<IIIIIIII")


def load_elf(data):
    if len(data) < HEADER.size:
        raise ValueError("Truncated ELF header")
    (ident, kind, machine, version, entry, phoff, _, flags, ehsize,
     phentsize, phnum, _, _, _) = HEADER.unpack_from(data)
    if ident[:4] != b"\x7fELF" or ident[4:7] != b"\x01\x01\x01":
        raise ValueError("Expected little-endian ELF32 version 1")
    if kind != 2 or machine != 243 or version != 1:
        raise ValueError("Expected a RISC-V ET_EXEC executable")
    if flags != 0:
        raise ValueError("Unsupported ELF flags (compressed/float/RVE or other ABI)")
    if ehsize != HEADER.size or phentsize != PROGRAM_HEADER.size or not phnum:
        raise ValueError("Invalid ELF/program header sizes or count")
    if phoff < ehsize or phoff + phnum * phentsize > len(data):
        raise ValueError("Truncated or invalid program header table")
    if entry != BASE:
        raise ValueError(f"Hardware reset vector requires entry 0x{BASE:08x}")

    image = bytearray(LIMIT - BASE)
    occupied = bytearray(len(image))
    high = 0
    executable_entry = False
    for index in range(phnum):
        ptype, offset, vaddr, paddr, filesz, memsz, permissions, align = (
            PROGRAM_HEADER.unpack_from(data, phoff + index * phentsize))
        if ptype in (2, 3):
            raise ValueError("Dynamic linking/interpreters are unsupported")
        if ptype != 1:
            continue
        if filesz > memsz or offset + filesz > len(data):
            raise ValueError("Invalid or truncated PT_LOAD segment")
        if not memsz:
            continue
        if paddr != vaddr:
            raise ValueError("PT_LOAD physical and virtual addresses must match")
        if vaddr < BASE or vaddr + memsz > LIMIT:
            raise ValueError("PT_LOAD exceeds the current 1 KiB RAM")
        if align not in (0, 1) and (
                align & (align - 1) or (vaddr - offset) % align):
            raise ValueError("Invalid PT_LOAD alignment")
        start, end = vaddr - BASE, vaddr - BASE + memsz
        if any(occupied[start:end]):
            raise ValueError("Overlapping PT_LOAD segments are unsupported")
        occupied[start:end] = b"\x01" * memsz
        image[start:start + filesz] = data[offset:offset + filesz]
        # Remaining memory in the segment is zero-initialized, including BSS.
        high = max(high, end)
        if permissions & 1 and vaddr <= entry and entry + 4 <= vaddr + filesz:
            executable_entry = True
    if not executable_entry:
        raise ValueError("Entry must point to at least four file-backed executable bytes")
    high = (high + 3) & ~3
    return [word[0] for word in struct.iter_unpack("<I", image[:high])]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("elf", type=Path)
    parser.add_argument("out", type=Path)
    args = parser.parse_args()
    try:
        words = load_elf(args.elf.read_bytes())
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    args.out.write_text("".join(f"{word:08x}\n" for word in words), encoding="ascii")
    print(f"Wrote {args.out}: {len(words)} words including BSS/gap zero fill")
    print("Offline only: CPU ISA support and hardware JTAG remain unverified.")


if __name__ == "__main__":
    main()
