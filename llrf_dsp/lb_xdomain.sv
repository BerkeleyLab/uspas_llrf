// Copies of the localbus write port in the dsp (lb_dsp), dac (lb_dac) and
// gt_rxclk (lb_evr) domains, for the register decode in those domains.
module lb_xdomain #(
    parameter int LB_ADW = 18,
    parameter int LB_DW = 32
) (
    input                   lb_clk,
    input                   lb_write,
    input      [LB_ADW-1:0] lb_addr,
    input      [LB_DW-1:0]  lb_data,

    input                   lb_dsp_clk,
    output                  lb_dsp_write,
    output     [LB_ADW-1:0] lb_dsp_addr,
    output     [LB_DW-1:0]  lb_dsp_data,

    input                   lb_dac_clk,
    output                  lb_dac_write,
    output     [LB_ADW-1:0] lb_dac_addr,
    output     [LB_DW-1:0]  lb_dac_data,

    input                   lb_evr_clk,
    output                  lb_evr_write,
    output     [LB_ADW-1:0] lb_evr_addr,
    output     [LB_DW-1:0]  lb_evr_data
);

data_xdomain #(.size(LB_ADW+LB_DW)) lb_to_1x (
    .clk_in(lb_clk), .gate_in(lb_write), .data_in({lb_addr, lb_data}),
    .clk_out(lb_dsp_clk), .gate_out(lb_dsp_write), .data_out({lb_dsp_addr, lb_dsp_data})
);

data_xdomain #(.size(LB_ADW+LB_DW)) lb_to_2x (
    .clk_in(lb_clk), .gate_in(lb_write), .data_in({lb_addr, lb_data}),
    .clk_out(lb_dac_clk), .gate_out(lb_dac_write), .data_out({lb_dac_addr, lb_dac_data})
);

data_xdomain #(.size(LB_ADW+LB_DW)) lb_to_3x (
    .clk_in(lb_clk), .gate_in(lb_write), .data_in({lb_addr, lb_data}),
    .clk_out(lb_evr_clk), .gate_out(lb_evr_write), .data_out({lb_evr_addr, lb_evr_data})
);

endmodule
