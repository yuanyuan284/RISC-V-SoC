# Stage 2: fixed BootROM and UART software loading

Status: RTL simulation and bitgen passed; apps A and B passed physical board
tests using the same bitstream file. SW2-only reset and UART software reload
also passed without FPGA reconfiguration.
Historical Stage 1 outputs remain locally under `build/stage1/`; source inputs
now use the shared `rtl/`, `fw/`, `tb/`, and `script/` layout.

## Latest physical-board check (2026-10-11)

With the already configured `stage2_uart.bit`, COM3 uploaded `app_b.elf`
after one SW2 reset. The uploader reported
`Application output: b'APP B: same FPGA, new C!'` and
`BootROM accepted CRC and acknowledged application launch.` TD was not opened
and no bitstream was downloaded for this run. Keep Tera Term closed while the
uploader owns COM3. The uploader now waits briefly for a repeated BootROM
banner after reset and reports following UART bytes if an ACK is wrong.

## Experimental JTAG software path

The separate `build/stage2/stage2_jtag.bit` includes the private 69-bit JTAG
loader. A full-SoC RTL simulation loaded the actual app A ELF image via a
simulated EF2 JTAG interface, read back every word, and ran it from RAM. It
then halted the same CPU, loaded and verified app B, and ran that too. UART
reported `APP A: UART loaded C!` and `APP B: same FPGA, new C!`. Run this check
with `script/run_stage2_jtag_sim.ps1`; it generates fresh simulation HEX files
from both ELFs. TD generated the bitstream with zero reported
setup/hold violations (3912/4480 LUT, 12/12 BRAM). Its SHA256 is
`d5661611a667ad9fe9b419bfac18dcc586511a5bbf2c074a09a0f0018d1aad30`.
The working UART bit retains SHA256
`a261d76379c6f04fd18d1ac7db1de99a0777c38b7642487b471b511d473b32bc`.

`script/elf_to_svf.py` validates an RV32 ELF, enforces the 896-byte Stage 2
image limit below the stack, and generates a signature-guarded
SVF with CPU hold, RAM writes, readback, RAM boot vector, and release. It
requires `--user-ir` explicitly. The EF2 user-chain IR is still unknown;
earlier candidate IRs did not return the loader signature. The JTAG bit has
not been downloaded to the board, and JTAG ELF loading has not been verified
on hardware. Do not execute generated SVF or guess IR values until the vendor
user-scan instruction is confirmed.

TD's read-only `list_bram` command was also checked as a possible vendor
route. For this device, both `EF2_4` and `EF2L45B` were rejected as unknown
device types. Moreover, the current program RAM is implemented in logic RAM,
not physical BRAM. No online BRAM read/write claim follows from this command.

## Checks completed

- Full VexRiscv, 1 KiB BootROM and 1 KiB RAM synthesized, placed and routed.
  The stage-2 bitstream is `build/stage2/stage2_uart.bit`.
- The timing report has zero setup/hold violations. BRAM usage is 12/12;
  VexRiscv PC asynchronous reset/set still has a synthesis warning.
- `script/run_stage2_sim.ps1` passes full RTL simulation: the same hardware
  receives and executes app A over UART, resets, then receives and executes
  a different app B. This is not a physical-board result.
- Cross-compiled RV32IM BootROM and both apps, checked ELF entry and stack
  sizes, and ran host UART/ELF unit tests. The UART uploader now accepts
  `.elf` directly, validates its load segments, fills BSS/gaps, enforces the
  896-byte image limit and produces the same wire frame as the `.bin` path
  for both built applications.
- On the physical EF2L45B board, COM3 received `APP A: UART loaded C!` and
  `APP B: same FPGA, new C!` after separate UART uploads. Both runs used the
  same bitstream file, SHA256
  `a261d76379c6f04fd18d1ac7db1de99a0777c38b7642487b471b511d473b32bc`.
  JTAG reconfigured that identical bit file before app B to trigger a fresh
  BootROM banner. Then SW2 alone reset the running app B, BootROM emitted a
  new banner, and COM3 uploaded app A again. The board printed
  `APP A: UART loaded C!` without another FPGA configuration.
- The uploader also accepted `build/stage2/app_b.elf` directly on the real
  board. Host-side ELF parsing produced the BootROM UART payload, and the
  board printed `APP B: same FPGA, new C!`. The same bit file was reconfigured
  only to trigger a fresh reset for this separate test.

## Prototype protocol

BootROM emits `BOOT UART\r\n` after each FPGA reset. Host sends a 16-byte
little-endian header: ASCII RV32, padded BIN byte length, entry address,
IEEE CRC32 of the padded payload. Each received byte is acknowledged with A;
H accepts the header, E rejects the header/checksum, and G acknowledges CRC
success before transferring execution. Host waits for every byte ACK.

The prototype uses current RAM at 0x80000000 with 1024 bytes; the upper 128
bytes are reserved for the BootROM stack, leaving 896 bytes of image capacity.
Entry is fixed at 0x80000000. Applications require their own startup/stack and
initialized data/BSS handling. Only one application is loaded per hardware
reset; no instruction-cache invalidation for jumping back into BootROM is
implemented. For `.elf` input the host validates load addresses, entry point,
segment overlap and payload size before producing the same BIN-style payload;
the BootROM itself does not parse ELF.

## Required before claiming hardware success

1. Release COM3 from Tera Term, then run `script/uart_upload.py` before JTAG
   configuration so it sees the fresh BootROM banner. `--expect-text` checks
   actual application output. Configure Stage 2 with
   `script/configure_stage2_fpga.tcl`; this only programs volatile FPGA fabric.
2. For another software image, keep the FPGA configured, release COM3 from
   Tera Term, start the uploader, then press and release SW2 (P55,
   active-high reset). This SW2-only path was verified by switching app B
   back to app A without another bit download.
3. Later: load ELF over JTAG with debug/halt control. ELF input to the UART
   uploader is a host-side conversion to the current BootROM protocol, not
   JTAG software loading.

Do not run `script/uart_upload.py` against stage-1: it intentionally refuses to
transmit without the BootROM banner. Tera Term must release the serial port
before a later verified hardware test. PySerial is needed for real transfer,
but not for offline protocol tests.
