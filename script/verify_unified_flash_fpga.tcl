set root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $root build unified stage3_unified.bit]
if {![file isfile $bit]} {
    error "Unified bitstream missing; run build_unified_td.ps1 -Bitstream first"
}
# Read-only comparison of the persistent FPGA configuration against this bitstream.
download -mode verify_spi -bit $bit -cable 0 -spd 7 -sec 64
