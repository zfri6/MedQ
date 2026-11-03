import_db pr.db
read_sdc io.sdc
update_timing -mode final
report_timing_summary -ep_num 1 -file io.timing
report_timing_exception -ep_num 50 -file io_exception.timing
export_sdc -file actual.sdc
puts "IO_DONE"
exit
