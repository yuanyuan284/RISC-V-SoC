set root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $root build stage3 stage3_uart.bit]
if {![file exists $bit]} {
    error "Stage-3 bitstream missing; run build_stage3_td.ps1 first"
}
# SRAM configuration only. No Flash erase/write and no private JTAG IR scans.
download -mode jtag -bit $bit -cable 0 -spd 7 -sec 64
