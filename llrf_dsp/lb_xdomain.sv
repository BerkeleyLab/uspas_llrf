// Copies of the localbus write port in the dsp (lb1), dac (lb2) and
// gt_rxclk (lb3) domains, for the register decode in those domains.
module lb_xdomain #(
    parameter int LB_ADW = 18,
    parameter int LB_DW = 32
) (
    input                   lb_clk,
    input                   lb_write,
    input      [LB_ADW-1:0] lb_addr,
    input      [LB_DW-1:0]  lb_data,

    input                   lb1_clk,
    output                  lb1_write,
    output     [LB_ADW-1:0] lb1_addr,
    output     [LB_DW-1:0]  lb1_data,

    input                   lb2_clk,
    output                  lb2_write,
    output     [LB_ADW-1:0] lb2_addr,
    output     [LB_DW-1:0]  lb2_data,

    input                   lb3_clk,
    output                  lb3_write,
    output     [LB_ADW-1:0] lb3_addr,
    output     [LB_DW-1:0]  lb3_data
);

data_xdomain #(.size(LB_ADW+LB_DW)) lb_to_1x (
    .clk_in(lb_clk), .gate_in(lb_write), .data_in({lb_addr, lb_data}),
    .clk_out(lb1_clk), .gate_out(lb1_write), .data_out({lb1_addr, lb1_data})
);

data_xdomain #(.size(LB_ADW+LB_DW)) lb_to_2x (
    .clk_in(lb_clk), .gate_in(lb_write), .data_in({lb_addr, lb_data}),
    .clk_out(lb2_clk), .gate_out(lb2_write), .data_out({lb2_addr, lb2_data})
);

data_xdomain #(.size(LB_ADW+LB_DW)) lb_to_3x (
    .clk_in(lb_clk), .gate_in(lb_write), .data_in({lb_addr, lb_data}),
    .clk_out(lb3_clk), .gate_out(lb3_write), .data_out({lb3_addr, lb3_data})
);

endmodule
