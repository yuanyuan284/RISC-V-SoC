set root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $root build debug stage3_debug.bit]
if {![file exists $bit]} {
    error "Debug bitstream missing; run build_debug_td.ps1 first"
}
# SRAM configuration only, using AL-Link Mini. CPU debugging uses a separate TAP.
download -mode jtag -bit $bit -cable 0 -spd 7 -sec 64
