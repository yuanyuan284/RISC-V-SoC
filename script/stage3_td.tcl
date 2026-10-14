open_project stage3_uart.prj
import_device ef2_4.db -package EF2L45LG144B
elaborate -top stage3_top
set root [file normalize [file join [file dirname [info script]] ..]]
read_adc [file join $root constraints uart.adc]
optimize_rtl
read_sdc [file join $root constraints uart.sdc]
optimize_gate -maparea stage3_uart_gate.area
legalize_phy_inst
export_db stage3_uart_gate.db
place
route
report_area -io_info -file stage3_uart_phy.area
export_db stage3_uart_pr.db
start_timer
report_timing -mode FINAL -net_info -rpt_autogen true -file stage3_uart.timing
export_bid stage3_uart_inst.bid
bitgen -bit stage3_uart.bit
