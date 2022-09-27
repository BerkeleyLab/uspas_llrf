create_clock -period 8.0 -name rx_clk [get_ports RGMII_RX_CLK]
create_clock -name sysclk -period 8.0 [get_ports GTPREFCLK_P]
# Max sampling rate 125 MHz, 2-Lanes 16-bit serialzation t_ser = 1/(8*fs) = 1ns
create_clock -period 2.0 -name adc0_clk [get_ports ZEST_ADC_DCO_P[0]]
create_clock -period 2.0 -name adc1_clk [get_ports ZEST_ADC_DCO_P[1]]

create_clock -period 8 -name dac_clk  [get_ports ZEST_DAC_DCO_P]
create_clock -period 8 -name clk_to_fpga0 [get_ports ZEST_CLK_TO_FPGA_P[0]]
create_clock -period 8 -name clk_to_fpga1 [get_ports ZEST_CLK_TO_FPGA_P[1]]

#   For phase_diff
set_false_path -from [get_clocks clk_out1_int] -to [get_clocks clk_out0_int]

set_clock_groups -asynchronous \
-group [get_clocks  -include_generated_clocks adc0_clk] \
-group [get_clocks  -include_generated_clocks adc1_clk] \
-group [get_clocks  -include_generated_clocks dac_clk] \
-group [get_clocks  -include_generated_clocks clk_to_fpga0] \
-group [get_clocks  -include_generated_clocks clk_to_fpga1] \
-group [get_clocks -include_generated_clocks rx_clk] \
-group [get_clocks -include_generated_clocks sysclk]
