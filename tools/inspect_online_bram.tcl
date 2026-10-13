# Read-only inventory of BRAM visible through TD on the connected device.
open_project stage2_uart.prj
if {[catch {list_bram -device EF2L45B -cable 0} result]} {
    puts "BRAM_INVENTORY_ERROR: $result"
} else {
    puts "BRAM_INVENTORY: $result"
}
