import_db pr.db
update_timing -mode final
set_sippin_assignment {clk} { IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; }
set_sippin_assignment {dq[*]} { IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; PULLTYPE = NONE; }
set_sippin_assignment {clk} { ABC_INVALID = 1; }
puts "SDRAMPROP [get_property ATTRIBUTES [get_cells {*u_device/sdram}]]"
puts "DONE"
exit
