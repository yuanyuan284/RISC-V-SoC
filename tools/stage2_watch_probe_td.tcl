open_project stage2_watch_probe.prj
import_device ef2_4.db -package EF2L45LG144B
elaborate -top watch_probe_top
set root [file normalize [file join [file dirname [info script]] ..]]
config_chipwatcher [file join $root stage2 watch_probe.cwc]
compile_watcher
read_adc [file join $root user_source constraint_source uart.adc]
optimize_rtl
read_sdc [file join $root stage2 watch_probe.sdc]
optimize_gate -maparea stage2_watch_probe_gate.area
legalize_phy_inst
place
route
report_area -io_info -file stage2_watch_probe_phy.area
start_timer
report_timing -mode FINAL -net_info -rpt_autogen true -file stage2_watch_probe.timing
