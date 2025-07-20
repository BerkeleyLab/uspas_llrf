module test_duc #(
    parameter int DWI = 18,
    parameter int DW = 16,
    parameter int DWLO = 18,
    localparam int INTP_FACTOR = 2
) (
    input dsp_clk,
    input dsp_reset,
    input signed [DWI-1:0] i_data_in,    // baseband input
    input signed [DWI-1:0] q_data_in,
    input i_data_valid,
    input q_data_valid,

    input dac_clk,
    input signed [DWLO-1:0] cosa,       // LO
    input signed [DWLO-1:0] sina,
    output signed [DW-1:0] dac_i_out,
    output signed [DW-1:0] dac_q_out
);

    logic signed [DWI-1:0] dac_i_data, dac_q_data;
    // interpolation
    dac_interp #(.DW(DW)) dac_interp_i (
        .dsp_clk        (dsp_clk),
        .dsp_reset      (dsp_reset),
        .dsp_din        (i_data_in),
        .dsp_din_valid  (1'b1),
        .dac_clk        (dac_clk),
        .dac_dout       (dac_i_data)
    );

    dac_interp #(.DW(DW)) dac_interp_q (
        .dsp_clk        (dsp_clk),
        .dsp_reset      (dsp_reset),
        .dsp_din        (q_data_in),
        .dsp_din_valid  (1'b1),
        .dac_clk        (dac_clk),
        .dac_dout       (dac_q_data)
    );

    cpxmul_fullspeed #(
        .DWI(DWI), .OUT_SHIFT(DW+1), .OWI(DW)
    ) duc_iq (
        .clk    (dac_clk),
        .re_a   (dac_i_data),
        .im_a   (dac_q_data),
        .re_b   (cosa),
        .im_b   (sina),
        .re_out (dac_i_out),
        .im_out (dac_q_out)
    );

endmodule