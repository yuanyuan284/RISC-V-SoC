"""Generate a guarded JTAG SVF from a constrained RISC-V ELF.

Offline only. The EF2 user scan IR must be independently confirmed before use.
"""

import argparse
from pathlib import Path

from elf_to_hex import load_elf
from hex_to_svf import generate

MAX_STAGE2_IMAGE = 896


def svf_from_elf(data, user_ir):
    words = load_elf(data)
    if len(words) * 4 > MAX_STAGE2_IMAGE:
        raise ValueError("Stage-2 image exceeds 896 bytes reserved below the stack")
    return generate(words, user_ir), len(words)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("elf", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--user-ir", type=lambda value: int(value, 0), required=True)
    args = parser.parse_args()
    try:
        if not 0 <= args.user_ir <= 255:
            raise ValueError("User IR must fit in 8 bits")
        svf, word_count = svf_from_elf(args.elf.read_bytes(), args.user_ir)
        args.out.write_text(svf, encoding="ascii")
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    print(f"Wrote {args.out}: {word_count} words including BSS/gap zero fill")
    print("Do not execute: EF2 user scan IR and hardware JTAG loading remain unverified.")


if __name__ == "__main__":
    main()
