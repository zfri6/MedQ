import_db {pr.db}
puts "SDRAM_CELL [get_cells {*u_device/sdram}]"
list_property [get_cells {*u_device/sdram}]
puts "SDRAM_PINS [get_pins {*u_device/sdram.*}]"
report_param -all -file params.txt
report_timing_ignored -file ignored.timing -ep_num 100
export_sdc -file actual.sdc
report_clock_utilization -file clocks.txt
puts "PROBE_DONE"
exit
