# EF2 ChipWatcher JTAG reset timing reproducer

Device: EF2L45LG144B
TD: 5.6.119222 (Windows)

The standalone counter design `rtl/watch_probe_top.v` uses only `clk_ref`,
`i_rst`, `rx`, and `tx`. `watch_probe.cwc` samples `tx` on `clk_ref`.
`watch_probe.sdc` constrains `clk_ref` to 100 ns. The original board ADC
assigns the four pins.

Run from the repository root:

```powershell
& .\tools\prepare_stage2_watch_probe.ps1
Push-Location .\stage2\build
& 'D:\TD_5.6.5_Release_119.222\bin\td_commands_prompt.exe' '..\..\tools\stage2_watch_probe_td.tcl'
Pop-Location
```

No bitstream is generated or downloaded by this flow. In
`build/stage2_watch_probe.timing`, final timing reports 0 setup errors and
1 hold error. The failing removal check is from `u.jrstn` to
`cw_top/wrapper_cwc_top/cfg_int_inst/tap_inst/rst_reg_syn_5.sr` on `jtck`,
with -2.145 ns slack. The TAP is supplied by TD in `cw/tap.v`, where
`rst` is set asynchronously on `posedge jrstn`.

The full VexRiscv UART SoC with ChipWatcher has the same type of violation
(-2.048 ns), while the validated SoC without ChipWatcher has zero reported
setup and hold errors. A separate RX/TX FIFO module name was required to
avoid `SYN-8490` during ChipWatcher insertion; that synthesis issue is
resolved in the current watcher experiment.

Question for Anlogic support: For TD 5.6.119222 and EF2L45LG144B, is the
ChipWatcher `jrstn` to `tap_inst/rst_reg` removal check a valid hardware
requirement? If so, what is the supported fix? If it is an assertion-only
or otherwise false timing path, please provide the exact official SDC
constraint and its scope. Is there a TD release that fixes this report?

Do not download `build/stage2_uart_chipwatch.invalid_bit`; it was generated
before the timing violation was found and is retained only for diagnosis.

The Anlogic EF2L45BG256B BSDL distributed through the official FAQ lists
IR 0x10 as `PROG_USERCODE` and 0x03 as `INTEST`. Earlier experimental
`td_project/probe_10.svf` and `probe_03.svf` must not be rerun. The BSDL is
for a different package, so it is reference evidence only; it does not
document the user scan instruction for EF2L45LG144B. Its IDCODE constant
is `0x03004C37`, matching the read-only IDCODE check on the connected board.

On 2026-10-11, a read-only IDCODE scan passed on the connected board.
The BSDL `USERCODE` IR 0x07 was read using a full 32-bit compare, yielding
`0x00190000`. The validated `stage2_uart.bit` bitgen log records
`0x007E0000`, so current USERCODE does not establish that this bitstream is
loaded; it also does not establish why the value differs. No configuration
or Flash write was done in this check. The unverified JTAG loader launchers
are disabled to prevent accidental use of configuration or test IR codes.

Additional question for Anlogic support: For EF2L45LG144B, which IR
opcode(s) route the TAP to `EF2_PHY_CONFIG.jscanen[1:0]` and `jtdo[1:0]`?
Please provide the `jtag8_ipa/ipb` semantics and TDO selection protocol.
The available BSDL lists configuration, boundary-test, IDCODE, and
USERCODE instructions but no documented user scan instruction. The
`0x00190000` USERCODE read differs from the `0x007E0000` bitgen log;
please clarify whether USERCODE reflects the active SRAM image, internal
Flash contents, or a separately programmable register.

A diagnostic attempt used `get_pins` on the timing-report names `u.jrstn`
and `cw_top/.../rst_reg_syn_5.sr`. TD resolved both collections to empty
strings, then accepted `set_false_path -hold -from  -to ` and reported zero
hold errors. That result is invalid: the exception did not identify the
intended path and may have suppressed unrelated checks. No false-path
constraint is part of the retained build flows.
