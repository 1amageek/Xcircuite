create_clock -name scan_clock -period 10 [get_ports clock]
set_case_analysis 1 [get_ports test_mode]
set_case_analysis 1 [get_ports scan_enable_0]
