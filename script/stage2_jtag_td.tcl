open_project stage2_jtag.prj
import_device ef2_4.db -package EF2L45LG144B
elaborate -top stage2_jtag_top
set root [file normalize [file join [file dirname [info script]] ..]]
read_adc [file join $root constraints uart.adc]
optimize_rtl
read_sdc [file join $root constraints uart.sdc]
optimize_gate -maparea stage2_jtag_gate.area
legalize_phy_inst
export_db stage2_jtag_gate.db
place
route
report_area -io_info -file stage2_jtag_phy.area
export_db stage2_jtag_pr.db
start_timer
report_timing -mode FINAL -net_info -rpt_autogen true -file stage2_jtag.timing
export_bid stage2_jtag_inst.bid
bitgen -bit stage2_jtag.bit
