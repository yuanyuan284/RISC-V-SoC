# Full-capacity transfer through DMI/progbuf, followed by a real application ELF.
init
halt
if {![info exists validation_output]} { set validation_output build/debug }
load_image [file join $validation_output ram-pattern.bin] 0x80000000 bin
verify_image [file join $validation_output ram-pattern.bin] 0x80000000 bin
dump_image [file join $validation_output ram-readback.bin] 0x80000000 65536
echo {PASS full 65536-byte RAM JTAG transfer and verification}
load_image build/stage3/app_a.elf
verify_image build/stage3/app_a.elf
echo {PASS Stage3 application ELF load and verification}

# Run, replace, and run the same cached instruction address without a reset.
write_memory 0x80000000 32 {0x00100513 0x0000006f}
set_reg {pc 0x80000000 a0 0}
step
if {[dict get [get_reg -force {a0}] a0] != 1} { error {Initial code execution failed} }
write_memory 0x80000000 32 {0x00900513 0x0000006f}
set_reg {pc 0x80000000 a0 0}
step
if {[dict get [get_reg -force {a0}] a0] != 9} { error {Reload executed stale instructions} }
echo {PASS instruction cache coherency on code reload}
shutdown
