module test_duc #(
    parameter int DWI = 18,
    parameter int DW = 16,
    parameter int DWLO = 18
) (
    input dsp_clk,
    input signed [DWI-1:0] i_data_in,    // baseband input
    input signed [DWI-1:0] q_data_in,
    input signed [DWLO-1:0] cosa,       // LO
    input signed [DWLO-1:0] sina,
    input dac_clk,
    output signed [DW-1:0] dac_i_out,
    output signed [DW-1:0] dac_q_out
);

    logic signed [DW-1:0] dac_in_data_i, dac_in_data_q;
    cpxmul_fullspeed #(
        .DWI(DWI), .OUT_SHIFT(DW+1), .OWI(DW)
    ) duc_iq (
        .clk    (dsp_clk),
        .re_a   (i_data_in),
        .im_a   (q_data_in),
        .re_b   (cosa),
        .im_b   (sina),
        .re_out (dac_in_data_i),
        .im_out (dac_in_data_q)
    );

    // interpolation
    localparam [DW:0] DAC_INTERP_COEFF = (2**(DW-1));

    zest_dac_interp #(.DW(DW)) dac_interp_i (
        .dsp_clk        (dsp_clk),
        .din            (dac_in_data_i),
        .coeff          (DAC_INTERP_COEFF),
        .dac_clk        (dac_clk),
        .dout           (dac_i_out)
    );

    zest_dac_interp #(.DW(DW)) dac_interp_q (
        .dsp_clk        (dsp_clk),
        .din            (dac_in_data_q),
        .coeff          (DAC_INTERP_COEFF),
        .dac_clk        (dac_clk),
        .dout           (dac_q_out)
    );

endmodule