import_db pr.db
read_sdc sip.sdc
update_timing -mode final
report_timing_summary -ep_num 1 -file sip.timing
export_sdc -file actual.sdc
puts "SIP_HOLD_DONE"
exit
