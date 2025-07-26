// Digital Up Converter (modulator)
// Inspired by:
// https://www.analog.com/media/en/technical-documentation/data-sheets/AD9174.pdf
// Figure 74. NCO Modulator Block Diagram

// y_n = (I_n + jQ_n)e^{jn\omega}
// \Re(y_n) = I_n\cos(n\omega) - Q_n\sin(n\omega)
// \Im(y_n) = Q_n\cos(n\omega) + I_n\sin(n\omega)

module dac_duc #(
    parameter int DWI = 18,
    parameter int DWO = 16,
    parameter int DWLO = 18,
    localparam int INTP_NUM = 2
) (
    input dsp_clk,
    input dsp_reset,
    input spectral_flip,
    input signed [DWI-1:0] i_data_in,    // base band input
    input signed [DWI-1:0] q_data_in,
    input i_data_valid,
    input q_data_valid,

    input dac_clk,
    input signed [DWLO-1:0] cosa,       // LO in dac_clk
    input signed [DWLO-1:0] sina,
    output signed [DWO-1:0] dac_i_out,
    output signed [DWO-1:0] dac_q_out
);

    wire signed [DWI-1:0] dac_i_data, dac_q_data;

    // delay: 8 cycles in dac_clk domain
    interp_xdomain #(.DW(DWI), .INTP_NUM(INTP_NUM)) interp_i (
        .in_clk         (dsp_clk),
        .in_reset       (dsp_reset),
        .in_data        (i_data_in),
        .in_data_valid  (i_data_valid),
        .out_clk        (dac_clk),
        .out_data       (dac_i_data)
    );

    // delay: 8 cycles in dac_clk domain
    interp_xdomain #(.DW(DWI), .INTP_NUM(INTP_NUM)) interp_q (
        .in_clk         (dsp_clk),
        .in_reset       (dsp_reset),
        .in_data        (q_data_in),
        .in_data_valid  (q_data_valid),
        .out_clk        (dac_clk),
        .out_data       (dac_q_data)
    );

    wire signed [DWLO-1:0] sin_i = spectral_flip ? -sina : sina;
    cpxmul_fullspeed #(
        .DWI(DWI), .OUT_SHIFT(DWO+1), .OWI(DWO)
    ) duc_iq (
        .clk    (dac_clk),
        .re_a   (dac_i_data),
        .im_a   (dac_q_data),
        .re_b   (cosa),
        .im_b   (sin_i),
        .re_out (dac_i_out),
        .im_out (dac_q_out)
    );

endmodule