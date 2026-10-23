set root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $root build unified stage3_unified.bit]
if {![file exists $bit]} {
    error "Unified bitstream missing; run build_unified_td.ps1 -Bitstream first"
}
# Configure FPGA SRAM only; leave internal configuration and MCU Flash unchanged.
download -mode jtag -bit $bit -cable 0 -spd 7 -sec 64
