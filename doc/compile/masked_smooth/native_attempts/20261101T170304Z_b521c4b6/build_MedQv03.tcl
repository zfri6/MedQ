# Explicit seed follows installed TD doc/scripts/MultiSeed.tcl.
import_db {prj/td/output/MedQv03_gate.db}
set_param place seed 11
legalize_phy_inst
update_timing
set_param route effort routability
place
export_db prj/td/output/MedQv03_place.db
route
fix_hold
report_area -io_info -file prj/td/reports/MedQv03_phy.area
update_timing -mode final
report_timing_status -file prj/td/reports/MedQv03_phy.ts
report_timing_summary -ep_num 500 -file prj/td/reports/MedQv03_pr.timing
report_timing_exception -file prj/td/reports/MedQv03_exception.timing
report_timing_ignored -ep_num 500 -file prj/td/reports/MedQv03_ignored.timing
check_timing -verbose -file prj/td/reports/MedQv03_constraint_health.rpt
export_db prj/td/output/MedQv03_pr.db
puts "MEDQ_STAGE_IMPLEMENTED"
puts "MEDQ_FLOW_DONE_IMPLEMENT"
exit
