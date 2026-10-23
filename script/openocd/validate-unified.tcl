proc expect_equal {actual expected label} {
    if {$actual != $expected} { error "$label: got $actual, expected $expected" }
    echo "PASS $label"
}
init
halt
set initial_pc [dict get [get_reg -force {pc}] pc]
if {!($initial_pc >= 0x30050010 && $initial_pc < 0x30060000) &&
    !($initial_pc >= 0x80008000 && $initial_pc < 0x8000f000)} {
    error "CPU did not halt in XIP or RAM hot code: $initial_pc"
}
expect_equal [lindex [read_memory 0x30050000 32 1] 0] 0x31504958 {XIP header through CPU JTAG}

# The application uses low RAM below 0x80004160; this is simulation-only scratch.
write_memory 0x80007000 32 {0x00100513 0x00250513 0x0000006f}
set_reg {pc 0x80007000 a0 0 mstatus 0 mie 0}
step
expect_equal [dict get [get_reg -force {pc}] pc] 0x80007004 {unified step PC}
expect_equal [dict get [get_reg -force {a0}] a0] 1 {unified step register}
step
expect_equal [dict get [get_reg -force {a0}] a0] 3 {unified second step register}
set_reg {pc 0x80007000 a0 0}
bp 0x80007008 4 hw
resume
wait_halt 5000
expect_equal [dict get [get_reg -force {pc}] pc] 0x80007008 {unified hardware breakpoint}
rbp 0x80007008
echo {PASS unified XIP FreeRTOS CPU JTAG halt, memory, step and hardware breakpoint}
shutdown
