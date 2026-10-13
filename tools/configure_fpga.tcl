set root [file normalize [file join [file dirname [info script]] ..]]
download -mode jtag -bit [file join $root td_project demo14_vexriscv_stage1_verified.bit] -cable 0 -spd 7 -sec 64
