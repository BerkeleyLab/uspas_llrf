module dac_interp #(
    parameter integer DW=16,
    parameter integer INTP_NUM=2
) (
    input dsp_clk,
    input dsp_reset,
    input signed [DW-1:0] dsp_din,
    input dsp_din_valid,
    input dac_clk,
    output signed [DW-1:0] dac_dout,
    output dac_dout_valid
);
    localparam integer INTERP_WIDTH = $clog2(INTP_NUM);

    wire [INTP_NUM*DW-1:0] dsp_interp;
    wire dsp_interp_valid;
    interpolator #(
        .SAMP_DW(DW), .SAMP_NUM(INTP_NUM)
    ) interp_i (
        .clk            (dsp_clk),
        .reset          (dsp_reset),
        .data_in        (dsp_din),
        .data_in_valid  (dsp_din_valid),
        .data_out       (dsp_interp),
        .data_out_valid (dsp_interp_valid)
    );

    wire [INTP_NUM*DW-1:0] dac_interp;
    wire dac_interp_valid;
    wire signed [DW-1:0] d1;
    data_xdomain #(.size(INTP_NUM*DW)) data_xdomain (
        .clk_in         (dsp_clk),
        .gate_in        (dsp_interp_valid),
        .data_in        (dsp_interp),
        .clk_out        (dac_clk),
        .gate_out       (dac_interp_valid),
        .data_out       (dac_interp)
    );

    serializer_multichannel #(
        .n_chan(INTP_NUM), .dw(DW), .l_to_r(0)
    ) serializer (
        .clk        (dac_clk),
        .sample_in  (dac_interp_valid),
        .data_in    (dac_interp),
        .gate_out   (dac_dout_valid),
        .stream_out (dac_dout)
    );
endmodule
