set root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $root build flash stage3_flash.bit]
if {![file exists $bit]} {
    error "Flash read bitstream missing; run build_flash_td.ps1 first"
}
# FPGA SRAM configuration only. This command does not program internal Flash.
download -mode jtag -bit $bit -cable 0 -spd 7 -sec 64
