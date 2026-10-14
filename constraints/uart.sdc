create_clock -name clk_ref -period 100 -waveform {0 50} [get_ports {clk_ref}]
derive_pll_clocks -gen_basic_clock
