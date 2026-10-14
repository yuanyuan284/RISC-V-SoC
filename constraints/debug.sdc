create_clock -name clk_ref -period 100 -waveform {0 50} [get_ports {clk_ref}]
derive_pll_clocks -gen_basic_clock
create_clock -name jtag_clock -period 1000 -waveform {0 500} [get_ports {jtag_tck}]
# JTAG adapters change TMS/TDI on TCK falling edges; the TAP samples rising.
set_input_delay -clock jtag_clock -clock_fall -max 100 [get_ports {jtag_tms jtag_tdi}]
set_input_delay -clock jtag_clock -clock_fall -min 0 [get_ports {jtag_tms jtag_tdi}]
set_output_delay -clock jtag_clock -max 100 [get_ports {jtag_tdo}]
set_output_delay -clock jtag_clock -min 0 [get_ports {jtag_tdo}]
# Only these asynchronous clock domains are exempted. The official DTM
# transfers stable command/response payloads using synchronized toggles.
set_clock_groups -asynchronous -group [get_clocks {jtag_clock}] -group [get_clocks {clk_ref pll*}]
