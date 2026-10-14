open_project stage3_debug.prj
import_device ef2_4.db -package EF2L45LG144B
elaborate -top stage3_debug_top
set root [file normalize [file join [file dirname [info script]] ..]]
read_adc [file join $root constraints debug.adc]
optimize_rtl
read_sdc [file join $root constraints debug.sdc]
optimize_gate -maparea stage3_debug_gate.area
legalize_phy_inst
export_db stage3_debug_gate.db
place
route
report_area -io_info -file stage3_debug_phy.area
export_db stage3_debug_pr.db
start_timer
report_timing -mode FINAL -net_info -rpt_autogen true -file stage3_debug.timing
export_bid stage3_debug_inst.bid
# Build script promotes this only when timing verification succeeds.
bitgen -bit stage3_debug.unverified_bit
