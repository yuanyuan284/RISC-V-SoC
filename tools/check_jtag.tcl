set root [file normalize [file join [file dirname [info script]] ..]]
program_svf -svf [file join $root td_project check_idcode.svf] -cable 0 -spd 1
