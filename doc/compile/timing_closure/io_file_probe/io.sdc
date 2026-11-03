set_max_delay -datapath_only 8.0 -from [get_ports {KEY* SW* UART_RX SD_MISO}]
set_max_delay -datapath_only 20.0 -from [all_registers] -to [get_ports {LED* SEG_DATA* SEG_SEL* BUZZER UART_TX}]
set_max_delay -datapath_only 8.0 -from [all_registers] -to [get_ports {SD_MOSI SD_SCLK SD_nCS}]
set_max_delay -datapath_only 4.0 -from [all_registers] -to [get_ports {HDMI_CLK_P HDMI_D0_P HDMI_D1_P HDMI_D2_P}]
