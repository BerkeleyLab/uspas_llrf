create_clock -period 8.0 -name rx_clk [get_ports RGMII_RX_CLK]
create_clock -name sysclk -period 8.0 [get_ports SYSCLK_P]
create_clock -name gtrefclk -period 7.994 [get_ports GTREFCLK_P]
# Max ADC sampling rate 125 MHz, 2-Lanes 16-bit serialization t_ser = 1/(8*fs) = 1ns
create_clock -period 2.0 -name adc0_clk [get_ports ZEST_ADC_DCO_P[0]]
create_clock -period 2.0 -name adc1_clk [get_ports ZEST_ADC_DCO_P[1]]

# Max DAC sampling rate 250MHz = 2 * f_ADC
create_clock -period 4.0 -name dac_clk  [get_ports ZEST_DAC_DCO_P]
create_clock -period 4.0 -name clk_to_fpga0 [get_ports ZEST_CLK_TO_FPGA_P[0]]
create_clock -period 4.0 -name clk_to_fpga1 [get_ports ZEST_CLK_TO_FPGA_P[1]]

#   For phase_diff
set_false_path -from [get_clocks clk_out1_int_1] -to [get_clocks clk_out0_int_1]

set_clock_groups -asynchronous \
-group [get_clocks -include_generated_clocks adc0_clk] \
-group [get_clocks -include_generated_clocks adc1_clk] \
-group [get_clocks -include_generated_clocks dac_clk] \
-group [get_clocks -include_generated_clocks clk_to_fpga0] \
-group [get_clocks -include_generated_clocks clk_to_fpga1] \
-group [get_clocks -include_generated_clocks rx_clk] \
-group [get_clocks -include_generated_clocks sysclk] \
-group [get_clocks -include_generated_clocks gtrefclk] \
-group [get_clocks -include_generated_clocks -of [get_pins {marble_inst/evr_gt_wrapper/gt_wrapper_i/gtx_inst.evr_gtx_i/inst/evr_gt_i/gt0_evr_gt_i/gtxe2_i/RXOUTCLK}]]
