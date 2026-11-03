import_db pr.db
update_timing -mode final
set_max_delay -datapath_only 8.0 -from [get_ports {KEY* SW* UART_RX SD_MISO}]
set_min_delay 0.0 -from [get_ports {KEY* SW* UART_RX SD_MISO}]
set_max_delay -datapath_only 20.0 -to [get_ports {LED* SEG_DATA* SEG_SEL* BUZZER UART_TX}]
set_min_delay 0.0 -to [get_ports {LED* SEG_DATA* SEG_SEL* BUZZER UART_TX}]
set_max_delay -datapath_only 8.0 -to [get_ports {SD_MOSI SD_SCLK SD_nCS}]
set_min_delay 0.0 -to [get_ports {SD_MOSI SD_SCLK SD_nCS}]
set_max_delay -datapath_only 4.0 -to [get_ports {HDMI_CLK_P HDMI_D0_P HDMI_D1_P HDMI_D2_P}]
set_min_delay 0.0 -to [get_ports {HDMI_CLK_P HDMI_D0_P HDMI_D1_P HDMI_D2_P}]
update_timing -mode final
report_timing_summary -ep_num 2 -file io.timing
report_timing_exception -ep_num 100 -file io_exception.timing
check_timing -verbose -file io_health.rpt
puts "IO_BUDGET_DONE"
exit
