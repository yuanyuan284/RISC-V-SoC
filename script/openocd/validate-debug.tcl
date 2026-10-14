proc expect_equal {actual expected label} {
    if {$actual != $expected} { error "$label: got $actual, expected $expected" }
    echo "PASS $label"
}
init
halt
set values [get_reg -force {pc}]
echo "Halted PC: [dict get $values pc]"

# Distinct physical banks and the last word of the complete 64 KiB RAM.
foreach {address value} {
    0x80000000 0x12345678
    0x80007ffc 0x98765432
    0x80008000 0xa5a5f00d
    0x8000bffc 0x23456789
    0x8000c000 0x3456789a
    0x8000dffc 0x456789ab
    0x8000e000 0x56789abc
    0x8000fffc 0xcafebabe
} {
    write_memory $address 32 [list $value]
    expect_equal [lindex [read_memory $address 32 1] 0] $value "RAM $address"
}

# addi a0,zero,1; addi a0,a0,2; sw a0,0(a1); jal zero,0.
write_memory 0x80000000 32 {0x00100513 0x00250513 0x00a5a023 0x0000006f}
set_reg {pc 0x80000000 a0 0 a1 0x8000fff0}
step
expect_equal [dict get [get_reg -force {pc}] pc] 0x80000004 {step 1 PC}
expect_equal [dict get [get_reg -force {a0}] a0] 1 {step 1 a0}
step
expect_equal [dict get [get_reg -force {pc}] pc] 0x80000008 {step 2 PC}
expect_equal [dict get [get_reg -force {a0}] a0] 3 {step 2 a0}
step
expect_equal [dict get [get_reg -force {pc}] pc] 0x8000000c {step 3 PC}
expect_equal [lindex [read_memory 0x8000fff0 32 1] 0] 3 {stepped store}

# ndmreset must leave the DM connected and RAM contents intact.
reset halt
expect_equal [lindex [read_memory 0x8000fffc 32 1] 0] 0xcafebabe {RAM survives reset}
set_reg {pc 0x80000000}
bp 0x80000008 4 hw
resume
wait_halt 5000
expect_equal [dict get [get_reg -force {pc}] pc] 0x80000008 {hardware breakpoint}
rbp 0x80000008
echo {PASS independent RISC-V JTAG RAM, registers, single-step, reset and breakpoint}
shutdown
