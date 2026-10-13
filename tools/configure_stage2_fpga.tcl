set root [file normalize [file join [file dirname [info script]] ..]]
download -mode jtag -bit [file join $root stage2 build stage2_uart.bit] -cable 0 -spd 7 -sec 64
