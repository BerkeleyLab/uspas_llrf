// data interpolation and domain crossing
module interp_xdomain #(
    parameter integer DW=16,
    parameter integer INTP_NUM=2
) (
    input in_clk,
    input in_reset,
    input signed [DW-1:0] in_data,
    input in_data_valid,
    input out_clk,
    output signed [DW-1:0] out_data,
    output out_data_valid
);
    wire [INTP_NUM*DW-1:0] in_interp;
    wire in_interp_valid;
    interpolator #(
        .SAMP_DW(DW), .SAMP_NUM(INTP_NUM)
    ) interp_i (
        .clk            (in_clk),
        .reset          (in_reset),
        .data_in        (in_data),
        .data_in_valid  (in_data_valid),
        .data_out       (in_interp),
        .data_out_valid (in_interp_valid)
    );

    wire [INTP_NUM*DW-1:0] out_interp;
    wire out_interp_valid;
    data_xdomain #(.size(INTP_NUM*DW)) data_xdomain (
        .clk_in         (in_clk),
        .gate_in        (in_interp_valid),
        .data_in        (in_interp),
        .clk_out        (out_clk),
        .gate_out       (out_interp_valid),
        .data_out       (out_interp)
    );

    serializer_multichannel #(
        .n_chan(INTP_NUM), .dw(DW), .l_to_r(0)
    ) serializer (
        .clk        (out_clk),
        .sample_in  (out_interp_valid),
        .data_in    (out_interp),
        .gate_out   (out_data_valid),
        .stream_out (out_data)
    );
endmodule
