set root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $root build rtos stage3_rtos.bit]
if {![file exists $bit]} { error "Build and verify stage3_rtos.bit first" }
# Configure only volatile FPGA logic through AL-Link Mini; no Flash operation.
download -mode jtag -bit $bit -cable 0 -spd 7 -sec 64
