set root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $root build flash stage3_flash.bit]
if {![file isfile $bit]} {
    error "Flash bitstream missing; run build_flash_td.ps1 first"
}
# Compare internal configuration Flash with the bitstream; no programming.
download -mode verify_spi -bit $bit -cable 0 -spd 7 -sec 64
