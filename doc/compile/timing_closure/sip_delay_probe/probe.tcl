import_db pr.db
set_sippin_assignment {dq[*]} { INDEL = 4.5; OUTDEL = 1.5; DRIVESTRENGTH = 8; }
set_sippin_assignment {addr[*] ba[*] we_n ras_n cas_n dm0 dm1 dm2 dm3 cke cs_n} { OUTDEL = 1.5; }
update_timing -mode final
report_timing_summary -ep_num 1 -file sip.timing
export_adc sip.adc
puts "DONE"
exit
