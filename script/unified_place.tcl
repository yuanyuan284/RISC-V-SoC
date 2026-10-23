open_project stage3_unified.prj
import_device ef2_4.db -package EF2L45LG144B
elaborate -top stage3_unified_top
set root [file normalize [file join [file dirname [info script]] ..]]
read_adc [file join $root constraints debug.adc]
optimize_rtl
read_sdc [file join $root constraints debug.sdc]
optimize_gate -maparea stage3_unified_gate.area
legalize_phy_inst
place
route
report_area -io_info -file stage3_unified_phy.area
start_timer
report_timing -mode FINAL -net_info -rpt_autogen true -file stage3_unified.timing
