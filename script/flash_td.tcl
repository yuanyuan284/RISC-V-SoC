open_project stage3_flash.prj
import_device ef2_4.db -package EF2L45LG144B
elaborate -top stage3_flash_top
set root [file normalize [file join [file dirname [info script]] ..]]
read_adc [file join $root constraints debug.adc]
optimize_rtl
read_sdc [file join $root constraints debug.sdc]
optimize_gate -maparea stage3_flash_gate.area
legalize_phy_inst
export_db stage3_flash_gate.db
place
route
report_area -io_info -file stage3_flash_phy.area
export_db stage3_flash_pr.db
start_timer
report_timing -mode FINAL -net_info -rpt_autogen true -file stage3_flash.timing
export_bid stage3_flash_inst.bid
bitgen -bit stage3_flash.unverified_bit -g {persist_bit:0}
