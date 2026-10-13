set root [file normalize [file join [file dirname [info script]] ..]]
program_svf -svf [file join $root td_project read_usercode.svf] -rdbk [file join $root td_project read_usercode_readback.txt] -cable 0 -spd 1
