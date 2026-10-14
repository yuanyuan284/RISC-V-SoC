set root [file normalize [file join [file dirname [info script]] ..]]
download -mode jtag -bit [file join $root build stage1 stage1_verified.bit] -cable 0 -spd 7 -sec 64
