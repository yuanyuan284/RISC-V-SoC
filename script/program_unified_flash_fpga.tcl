set root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $root build unified stage3_unified.bit]
if {![info exists ::env(SOC_CONFIRM_UNIFIED_CONFIG_FLASH)] ||
    $::env(SOC_CONFIRM_UNIFIED_CONFIG_FLASH) ne "PROGRAM_UNIFIED_CONFIG_FLASH"} {
    error "Set SOC_CONFIRM_UNIFIED_CONFIG_FLASH=PROGRAM_UNIFIED_CONFIG_FLASH only after a fresh full-Flash backup and explicit user authorization"
}
if {![file isfile $bit]} {
    error "Unified bitstream missing; run build_unified_td.ps1 -Bitstream first"
}
if {[file size $bit] > 0x50000} {
    error "Unified bitstream exceeds the 320 KiB configuration reserve"
}
# Persistent configuration Flash write; this is not an FPGA SRAM download.
download -mode program_spi -bit $bit -cable 0 -spd 7 -sec 64
