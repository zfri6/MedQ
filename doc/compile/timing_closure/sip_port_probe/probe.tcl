import_db pr.db
update_timing -mode final
puts "ALLPORTS [get_ports *]"
puts "ALLCLKS [get_clocks *]"
puts "FULLPIN [get_pins {u_sdram_ctrl_wrap/u_hardware/u_device/sdram.dq*}]"
puts "WILDPIN [get_pins {*u_device/sdram.dq*}]"
puts "SIPPORT [get_ports {*sdram*}]"
puts "DQPORT [get_ports {dq*}]"
set_input_delay -clock [get_clocks {*clkc?2?}] -max 4.5 [get_ports {dq*}]
set_output_delay -clock [get_clocks {*clkc?2?}] -max 1.5 [get_ports {dq* addr* ba* we_n ras_n cas_n dm*}]
report_timing_summary -ep_num 1 -file ports.timing
export_sdc -file ports.sdc
puts "PROBE_DONE"
exit
