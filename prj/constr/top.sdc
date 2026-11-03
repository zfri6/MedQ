# MedQ clock constraints. Real PLL frequencies/phases are inferred, not relaxed.
# 50 MHz supported by HX_CESHI_EG4S_BORD and clk_wize FIN=50.000.
create_clock -name clk_sys -period 20 -waveform {0 10} [get_ports {clk50mhz}]
# Infer the real 25/125 MHz relationship from the preserved generated wrapper.
derive_clocks -instance [get_cells {u_medq_pll/pll_inst}]
derive_clocks -instance [get_cells {u_sys_pll/pll_inst}]
# medq_pll: C0=125 MHz, C1=25 MHz; sys_pll: C0/C1=50 MHz, C2=50 MHz/+8ns.
# No global clock-group or false-path exceptions: preserve related-clock checks.
# Keep the conservative SIP max-output 5ns model, but use the correct negative
# output-delay sign for a positive 1ns SDRAM input hold requirement. This tightens
# the native default min=+1ns by 2ns; it does not relax a failing path.
set_output_delay -clock [get_clocks {u_sys_pll/pll_inst.clkc[2]}] -reference_pin [get_pins {u_sdram_ctrl_wrap/u_hardware/u_device/sdram.clk}] -max 5.0 [get_pins {u_sdram_ctrl_wrap/u_hardware/u_device/sdram.dq* u_sdram_ctrl_wrap/u_hardware/u_device/sdram.addr* u_sdram_ctrl_wrap/u_hardware/u_device/sdram.ba* u_sdram_ctrl_wrap/u_hardware/u_device/sdram.ras_n u_sdram_ctrl_wrap/u_hardware/u_device/sdram.cas_n u_sdram_ctrl_wrap/u_hardware/u_device/sdram.we_n u_sdram_ctrl_wrap/u_hardware/u_device/sdram.dm* u_sdram_ctrl_wrap/u_hardware/u_device/sdram.cke u_sdram_ctrl_wrap/u_hardware/u_device/sdram.cs_n}]
set_output_delay -clock [get_clocks {u_sys_pll/pll_inst.clkc[2]}] -reference_pin [get_pins {u_sdram_ctrl_wrap/u_hardware/u_device/sdram.clk}] -min -1.0 [get_pins {u_sdram_ctrl_wrap/u_hardware/u_device/sdram.dq* u_sdram_ctrl_wrap/u_hardware/u_device/sdram.addr* u_sdram_ctrl_wrap/u_hardware/u_device/sdram.ba* u_sdram_ctrl_wrap/u_hardware/u_device/sdram.ras_n u_sdram_ctrl_wrap/u_hardware/u_device/sdram.cas_n u_sdram_ctrl_wrap/u_hardware/u_device/sdram.we_n u_sdram_ctrl_wrap/u_hardware/u_device/sdram.dm* u_sdram_ctrl_wrap/u_hardware/u_device/sdram.cke u_sdram_ctrl_wrap/u_hardware/u_device/sdram.cs_n}]
# Per-interface local routing budgets; see timing_closure/io_contract.md.
# Asynchronous contacts/UART terminate at the first synchronizer, whose input
# cannot have a synchronous setup/hold relationship. Subsequent stages retain
# their full clock checks. SD mode 0 has >=40ns per data half-cycle.
set_max_delay -datapath_only 8.0 -from [get_ports {KEY* SW* UART_RX SD_MISO}]
set_max_delay -datapath_only 20.0 -from [all_registers] -to [get_ports {LED* SEG_DATA* SEG_SEL* BUZZER UART_TX}]
set_max_delay -datapath_only 8.0 -from [all_registers] -to [get_ports {SD_MOSI SD_SCLK SD_nCS}]
# Maximum FPGA-local DDR pad latency, not a board/HDMI receiver eye measurement.
set_max_delay -datapath_only 4.0 -from [all_registers] -to [get_ports {HDMI_CLK_P HDMI_D0_P HDMI_D1_P HDMI_D2_P}]
