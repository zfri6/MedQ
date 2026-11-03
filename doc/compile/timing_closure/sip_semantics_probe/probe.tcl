import_db pr.db
update_timing -mode final
puts "CLOCK_EXACT [get_clocks {u_sys_pll/pll_inst.clkc[2]}]"
puts "CLOCK_REGEX [get_clocks -regexp {u_sys_pll/pll_inst.clkc.2.}]"
puts "PIN_EXACT [get_pins {u_sdram_ctrl_wrap/u_hardware/u_device/sdram.clk}]"
puts "PROP_RESULT [catch {set_ip_property ABC_INVALID 1 [get_cells {u_sdram_ctrl_wrap/u_hardware/u_device/sdram}]} e] $e"
set_input_delay -clock {u_sys_pll/pll_inst.clkc[2]} -max 4.5 [get_pins {u_sdram_ctrl_wrap/u_hardware/u_device/sdram.dq*}]
set_output_delay -clock {u_sys_pll/pll_inst.clkc[2]} -max 1.5 [get_pins {u_sdram_ctrl_wrap/u_hardware/u_device/sdram.dq* u_sdram_ctrl_wrap/u_hardware/u_device/sdram.addr* u_sdram_ctrl_wrap/u_hardware/u_device/sdram.ba* u_sdram_ctrl_wrap/u_hardware/u_device/sdram.ras_n u_sdram_ctrl_wrap/u_hardware/u_device/sdram.cas_n u_sdram_ctrl_wrap/u_hardware/u_device/sdram.we_n u_sdram_ctrl_wrap/u_hardware/u_device/sdram.dm*}]
set_annotated_check -setup -max -from [get_pins {u_sdram_ctrl_wrap/u_hardware/u_device/sdram.clk}] -to [get_pins {u_sdram_ctrl_wrap/u_hardware/u_device/sdram.dq*}] 1.5
update_timing -mode final
report_timing_summary -ep_num 1 -file sip.timing
export_sdc -file sip.sdc
puts "DONE"
exit
