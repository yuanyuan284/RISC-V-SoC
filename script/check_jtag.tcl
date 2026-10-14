set root [file normalize [file join [file dirname [info script]] ..]]
program_svf -svf [file join $root script jtag check_idcode.svf] -cable 0 -spd 1
