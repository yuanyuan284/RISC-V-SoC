set root [file normalize [file join [file dirname [info script]] ..]]
file mkdir [file join $root build jtag]
program_svf -svf [file join $root script jtag check_usercode.svf] -rdbk [file join $root build jtag check_usercode_readback.txt] -cable 0 -spd 1
