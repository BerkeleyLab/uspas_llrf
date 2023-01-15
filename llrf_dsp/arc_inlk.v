module arc_inlk #(
    parameter N_CH = 3
) (
    input               clk,
    input [0:0]         reset_latch, // external single-cycle
    input [0:0]         reset_arc_dev,  // external
    input [7:0]         permit_mask, // external
    input [7:0]         test_arc_dev, // external

    // status readout
    output [N_CH-1:0]   permit_raw_out,
    output [N_CH-1:0]   permit_latch_out,
    output              permit_sum_out,

    // device interface
    input [N_CH-1:0]    dev_permit_in,
    output [N_CH-1:0]   dev_test_out,
    output              dev_reset_out
);

reg [N_CH-1:0] permit_latch_r=0;

always @(posedge clk) begin
    permit_latch_r <= dev_permit_in & ({N_CH{reset_latch}} | permit_latch_r);
end

assign dev_test_out = test_arc_dev[N_CH-1:0];
assign dev_reset_out = reset_arc_dev;

assign permit_latch_out = permit_latch_r;
assign permit_sum_out = & ( ~permit_mask[N_CH-1:0] | permit_latch_r);
endmodule
