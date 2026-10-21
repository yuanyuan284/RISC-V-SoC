set root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $root build flash stage3_flash.bit]
if {![info exists ::env(SOC_CONFIRM_CONFIG_FLASH)] ||
    $::env(SOC_CONFIRM_CONFIG_FLASH) ne "PROGRAM_CONFIG_FLASH"} {
    error "Set SOC_CONFIRM_CONFIG_FLASH=PROGRAM_CONFIG_FLASH after a verified full-Flash backup"
}
if {![file isfile $bit]} {
    error "Flash bitstream missing; run build_flash_td.ps1 first"
}
# Persistent EF2 configuration Flash write, not an FPGA SRAM download.
download -mode program_spi -bit $bit -cable 0 -spd 7 -sec 64
