create_clock -name sysclk -period 8.0 [get_ports GTPREFCLK_P]
# Max sampling rate 125 MHz, 2-Lanes 16-bit serialization t_ser = 1/(8*fs) = 1ns
create_clock -period 2.0 -name adc0_clk [get_ports ZEST_ADC_DCO_P[0]]
create_clock -period 2.0 -name adc1_clk [get_ports ZEST_ADC_DCO_P[1]]

# 500 * 11 / 12 / 4 = 114.6 MHz
create_clock -period 8.7 -name dac_clk  [get_ports ZEST_DAC_DCO_P]
create_clock -period 8.7 -name clk_to_fpga0 [get_ports ZEST_CLK_TO_FPGA_P[0]]
create_clock -period 8.7 -name clk_to_fpga1 [get_ports ZEST_CLK_TO_FPGA_P[1]]

# Clock                      Waveform(ns)         Period(ns)      Frequency(MHz)
# -----                      ------------         ----------      --------------
# adc0_clk                   {0.000 1.000}        2.000           500.000
#   ic_map[0].dco_buf_i_n_1  {1.000 5.000}        8.000           125.000
# adc1_clk                   {0.000 1.000}        2.000           500.000
#   ic_map[1].dco_buf_i_n_1  {1.000 5.000}        8.000           125.000
# dac_clk                    {0.000 4.350}        8.700           114.943
# clk_to_fpga0               {0.000 4.350}        8.700           114.943
# clk_to_fpga1               {0.000 4.350}        8.700           114.943
# sysclk                     {0.000 4.000}        8.000           125.000
#   clk_out0_int             {0.000 4.000}        8.000           125.000
#   clk_out1_int             {0.000 2.500}        5.000           200.000
#   mmcm_clkfbout            {0.000 4.000}        8.000           125.000

#   For phase_diff
set_false_path -from [get_clocks clk_out1_int] -to [get_clocks clk_out0_int]

set_clock_groups -asynchronous \
-group [get_clocks  -include_generated_clocks adc0_clk] \
-group [get_clocks  -include_generated_clocks adc1_clk] \
-group [get_clocks  -include_generated_clocks dac_clk] \
-group [get_clocks  -include_generated_clocks clk_to_fpga0] \
-group [get_clocks  -include_generated_clocks clk_to_fpga1] \
-group [get_clocks -include_generated_clocks sysclk]
