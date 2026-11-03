import_db pr.db
update_timing -mode final
set_input_delay -clock [get_clocks {u_sys_pll/pll_inst.clkc[2]}] -reference_pin [get_pins {u_sdram_ctrl_wrap/u_hardware/u_device/sdram.clk}] -max 4.5 [get_pins {u_sdram_ctrl_wrap/u_hardware/u_device/sdram.dq*}]
set_input_delay -clock [get_clocks {u_sys_pll/pll_inst.clkc[2]}] -reference_pin [get_pins {u_sdram_ctrl_wrap/u_hardware/u_device/sdram.clk}] -min 2.0 [get_pins {u_sdram_ctrl_wrap/u_hardware/u_device/sdram.dq*}]
set_output_delay -clock [get_clocks {u_sys_pll/pll_inst.clkc[2]}] -reference_pin [get_pins {u_sdram_ctrl_wrap/u_hardware/u_device/sdram.clk}] -max 1.5 [get_pins {u_sdram_ctrl_wrap/u_hardware/u_device/sdram.dq* u_sdram_ctrl_wrap/u_hardware/u_device/sdram.addr* u_sdram_ctrl_wrap/u_hardware/u_device/sdram.ba* u_sdram_ctrl_wrap/u_hardware/u_device/sdram.ras_n u_sdram_ctrl_wrap/u_hardware/u_device/sdram.cas_n u_sdram_ctrl_wrap/u_hardware/u_device/sdram.we_n u_sdram_ctrl_wrap/u_hardware/u_device/sdram.dm*}]
set_output_delay -clock [get_clocks {u_sys_pll/pll_inst.clkc[2]}] -reference_pin [get_pins {u_sdram_ctrl_wrap/u_hardware/u_device/sdram.clk}] -min -1.0 [get_pins {u_sdram_ctrl_wrap/u_hardware/u_device/sdram.dq* u_sdram_ctrl_wrap/u_hardware/u_device/sdram.addr* u_sdram_ctrl_wrap/u_hardware/u_device/sdram.ba* u_sdram_ctrl_wrap/u_hardware/u_device/sdram.ras_n u_sdram_ctrl_wrap/u_hardware/u_device/sdram.cas_n u_sdram_ctrl_wrap/u_hardware/u_device/sdram.we_n u_sdram_ctrl_wrap/u_hardware/u_device/sdram.dm*}]
update_timing -mode final
report_timing_summary -ep_num 1 -file annotated.timing
export_sdc -file annotated.sdc
puts "PROBE_DONE"
exit
