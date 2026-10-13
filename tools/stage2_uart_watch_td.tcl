open_project stage2_uart_chipwatch.prj
import_device ef2_4.db -package EF2L45LG144B
elaborate -top stage2_top
set root [file normalize [file join [file dirname [info script]] ..]]
config_chipwatcher [file join $root stage2 stage2_uart_watch.cwc]
compile_watcher
read_adc [file join $root user_source constraint_source uart.adc]
optimize_rtl
read_sdc [file join $root user_source constraint_source uart.sdc]
optimize_gate -maparea stage2_uart_chipwatch_gate.area
legalize_phy_inst
export_db stage2_uart_chipwatch_gate.db
place
route
report_area -io_info -file stage2_uart_chipwatch_phy.area
export_db stage2_uart_chipwatch_pr.db
start_timer
report_timing -mode FINAL -net_info -rpt_autogen true -file stage2_uart_chipwatch.timing
export_bid stage2_uart_chipwatch_inst.bid
