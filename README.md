# RISC-V SoC on Anlogic EF2

The current Stage 3 implements a VexRiscv RV32IM SoC with an 8 KiB BootROM,
64 KiB RAM and a Wishbone UART. Cross-compiled C applications produce ELF,
BIN and Intel HEX files. BootROM receives a BIN over UART at 115200 8N1,
checks CRC32 and jumps to RAM at `0x80000000`. Applications use newlib
`printf` and `snprintf`, including floating-point formatting.

Hardware validation on EF2L45LG144B (2026-10-13): two 42,424-byte applications
downloaded and executed successfully, printing `FLOAT=3.25`, `errors=0`
and `STAGE3 PASS`. Six malformed frame cases were rejected, followed by
successful recovery and execution of a valid BIN. TD reports zero setup
and hold errors. The upload limit is 60 KiB, with the top 4 KiB reserved
for the stack. Stage 3 SW2-only reload has not been separately tested.

- [Current implementation and commands](stage3/README.md)
- [Hardware validation and evidence](stage3/HARDWARE_VALIDATION.md)
- [Project progress in Chinese](agent.md)
- [Background and defense preparation in Chinese](report.md)

This repository is a snapshot of the entire project folder, including
source, firmware outputs, bitstreams, reports and build logs. Building
requires Tang Dynasty 5.6.119222, an RV32IM/ILP32 GCC toolchain, Python and
the external VexRiscv RTL referenced by the scripts. These installed tools
are not part of the project folder; the build scripts currently reference
local Windows paths. Third-party components retain their original notices.

The sections below document the earlier Stage 1 bring-up and JTAG
experiments. Their capacity and validation status do not describe Stage 3.

## Stage 1 Bring-Up History

EF2L45LG144B / TangDynasty bring-up project.

This is an intentionally tiny Stage-1 CPU configuration for the included
`soc_fw.hex`. The firmware uses only x5/x6 and LUI/ADDI/SW/JAL, so the CPU
implements only those instructions and an 8-register file (x0..x7).

The design has two bring-up paths at different validation stages:

- Hex ROM boot: `user_source/firmware/soc_fw.hex` is loaded into the ROM at
  `0x2000_0000` with `$readmemh`, and the CPU starts from ROM by default.
- JTAG-style RAM download: `jtag_wb_loader.v` writes firmware words into RAM at
  `0x8000_0000`, then switches the CPU reset vector to RAM and releases reset.
  This path is experimental: its EF2 user scan instruction has not yet been
  confirmed on hardware, so RAM download is not yet validated.

The rest of the design remains small: EF2 PLL, Wishbone ROM/RAM, UART, and the
JTAG loader. The goal is to keep the stage-1 resource footprint low before
adding CPU features back.

Open `td_project/demo14_vexriscv_stage1.al` in TangDynasty.

## UART board check

Connect the board TX pin P60 to the USB-UART adapter RXD, board RX pin P59
to adapter TXD, and connect their grounds. Use 3.3 V logic levels.
Open the terminal at 115200 baud, 8 data bits, no parity, 1 stop bit, and no
flow control before JTAG configuration. The firmware prints `Hello from C!`
with CR/LF once, then loops. It can be restarted using the FPGA reset input
P55; resetting the STM32 downloader is a different operation.

The first ADDI instruction must be `0d800313` (216) for the 25 MHz UART
prescaler. `d8000313` decodes to -640 and produces the wrong baud rate.
ROM initialization uses `../firmware/soc_fw.hex` relative to the HDL source
directory, avoiding TD's working-directory fallback.

## Repeatable TD build

Run from the project directory, without running the GUI flow at the same time:

```powershell
powershell -ExecutionPolicy Bypass -File tools\build_td.ps1
```

The script uses the TD-generated `syn_1` and `phy_1` Tcl scripts, records logs
as `build_cli.log` in each run directory, and checks that the outputs are new.
It copies the bitstream to `td_project/demo14_vexriscv_stage1_verified.bit`
only when the timing report contains zero setup and hold errors. This checks
the current constraints; it does not establish board-level functionality.

## JTAG loader frame format

The loader is connected to the EF2 dedicated JTAG port through
`EF2_PHY_CONFIG`, so it does not need extra GPIO pin assignments. It is a tiny
private download protocol, not the full OpenOCD/GDB RISC-V Debug Module. Select
the user JTAG scan chain, shift 69 bits LSB-first in `SHIFT-DR`, then enter
`UPDATE-DR` to commit:

Loader reset is sampled separately in the system and TCK clock domains.
The loader uses system reset, not the TAP reset, so a host TAP reset does not
change the running CPU's boot source. Its TCK reset sampler uses falling edges.
Hold system reset for at least three clocks in each domain, and allow at least
three clocks after release before a command.

```text
bit  0      write enable
bits 4:1    byte select
bits 36:5   byte address
bits 68:37  write data
```

The local control register is at `0xffff_fffc`:

- bit 0: boot from RAM at `0x8000_0000`
- bit 1: hold CPU reset during download

RAM commands are accepted only while the CPU is held in reset, at aligned
addresses in `0x80000000..0x800003ff`. Command payloads are latched at UPDATE-DR
and remain stable until a system-to-TCK acknowledgement is synchronized.
Wait for command completion before sending another nonzero frame. An all-zero
69-bit frame polls status without issuing a bus transaction. Malformed frames
or frames received while busy are ignored; they must not be counted as a
completed new command.

The 69-bit TDO response has data in bits 31:0, busy in bit 32, error in bit 33,
completion-valid in bit 34, completion toggle in bit 35, reserved bit 36, and
signature `0x4a544147` in bits 68:37. Every completed command flips the toggle.

For RAM boot, write control value 2 before downloading, value 3 after verifying
RAM (select RAM while keeping CPU reset asserted), then value 1 to run.

## Experimental SVF workflow

`tools/hex_to_svf.py` creates SVF with IDCODE/signature checks, RAM writes,
per-word readback checks, and the two-step RAM boot sequence. `--user-ir` must
be supplied explicitly; no EF2 user instruction is assumed confirmed.
`tools/make_demo_firmware.py` creates `jtag_demo.hex`, which prints
`Hello from JTAG!` to distinguish RAM execution from the ROM message.

`tools/check_jtag.tcl` was tested with AL-Link Mini: the EF2L45B IDCODE check
passed. `tools/configure_fpga.tcl` was tested and successfully configured SRAM.
`tools/bringup_jtag.tcl` configures FPGA then tests the user-chain signature.
`tools/program_ram.tcl` runs `td_project/soc_fw.svf`, whose signature guard
precedes all RAM writes. Do not run it as a successful download procedure
until a user-chain signature probe has passed.

Hardware probes with IR F0, 02, 03, 10, and 11 did not return the loader
signature. Setting `jtag8_ipa/ipb` to F0/F1 did not make IR F0 a user scan
instruction; those pins are left at zero rather than assuming they program IR.
The next required evidence is an EF2 user-JTAG instruction specification or
a working vendor ChipWatcher JTAG sequence. Current SVF artifacts use F0 as a
failed probe candidate, not as a confirmed instruction.

Generate a text frame file from the existing hex image:

```powershell
python tools\hex_to_jtag_frames.py user_source\firmware\soc_fw.hex td_project\soc_fw.jtag
```

## Offline ELF preparation (not hardware download)

`tools/elf_to_hex.py` accepts little-endian ELF32 RISC-V ET_EXEC files with
zero ELF flags. It uses PT_LOAD program headers, not section names, copies
file-backed bytes, and zero-fills BSS and gaps. All load segments must fit
the current 1 KiB RAM, have matching physical/virtual addresses, and not
overlap. The entry must be `0x80000000` with file-backed executable bytes:
the current loader cannot set an arbitrary reset vector. Dynamic linking,
compressed/float/RVE flags, malformed headers, and truncated files are rejected.

```powershell
python tools\elf_to_hex.py firmware.elf firmware_ram.hex
python -m unittest discover -s tools -p test_elf_to_hex.py -v
```

These seven tests use synthetic ELF fixtures. No real compiler-produced ELF
or ELF-on-board execution has been verified. Conversion does not establish
instruction compatibility: the stage-1 four-instruction CPU cannot execute
ordinary compiled C. A full generated VexRiscv is available locally under
`D:\fpga-3-softcores-master\vendor\vexriscv`, but has not been integrated or
resource/timing checked for this EF2 project. No cross compiler was found on
the current PATH during this check.

ChipWatcher instrumentation failed with KIT-8414 because the custom loader
already drives PHY_CONFIG jtdo[0], which ChipWatcher expects to be unconnected.
Keep `jtag_watch.cwc` disabled for the baseline project. Do not disconnect the
loader TDO merely to make ChipWatcher compile. Sharing the user chains needs
documented vendor support; ChipWatcher is not an ELF downloader.

An isolated Stage-2 watcher experiment confirmed TD can insert ChipWatcher
when the custom loader is disabled and PHY JTAG TDO is unconnected. However,
synthesis reported the sampled JTAG control signals as undriven and merged
their four bits into a constant net. No valid JTAG observation bit resulted.
The earlier watcher output was produced before actual ChipWatcher insertion
and has been renamed `stage2/build/stage2_watcher.invalid_bit` to prevent
accidental download. Keep the verified UART bit on the board.

## Candidate vendor BRAM access route

Read-only command discovery with `tools/inspect_ram_commands.tcl` confirmed
that this installed TD version exposes `list_bram`, `rdbk_bram`, and
`write_bram` (also 18/20/32 variants). Discovery runs help only for an explicit
allowlist and performs no hardware operation. Device compatibility, input
format, reset sequencing, and whether writes affect only program data remain
unverified. Do not treat these commands as a working ELF download procedure.

The current baseline reports zero physical BRAM blocks despite a RAM inference
hint. This route requires a separate tested BRAM-backed memory implementation,
plus reliable CPU hold/reset and execution after readback verification. Keep
the working baseline unchanged until those checks pass. Neither
`Update BRAM Data` bitstream patching nor reconfiguring the FPGA counts as
fixed-hardware software-only download.
