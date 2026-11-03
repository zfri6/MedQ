create_clock -name clk_sys -period 20 -waveform {0 10} [get_ports {clk50mhz}]
derive_clocks -instance [get_cells {u_medq_pll/pll_inst}]
derive_clocks -instance [get_cells {u_sys_pll/pll_inst}]
