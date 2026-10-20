// RX path (plan §2.2): the RX LO and one DDC per ADC channel, sharing the
// I/Q divider state.
module rx_chain
    import llrf_shell_pkg::*;
(
    input                 dsp_clk,
    input                 dsp_reset,
    input  [DW*N_ADC-1:0] adc_data_in,
    // RX LO
    input  [17:0]         dds_amplitude,
    input  [18:0]         dds_phase_shift,
    input  [31:0]         dds_phase_step,
    input  [11:0]         dds_modulo,

    output adc_t          adc [N_ADC],    // raw samples
    output bb_t           sig_i [N_ADC],  // baseband
    output bb_t           sig_q [N_ADC]
);

wire signed [DWLO-1:0] cosd, sind;
dds #(.DWLO(DWLO)) rx_dds (
    .clk          (dsp_clk),
    .reset        (dsp_reset),
    .amplitude    (dds_amplitude),
    .phase_shift  (dds_phase_shift),
    .phase_step_h (dds_phase_step[31:12]),
    .phase_step_l (dds_phase_step[11:0]),
    .modulo       (dds_modulo),
    .cos_out      (cosd),
    .sin_out      (sind)
);

// synchronize I/Q divider state for multiple DDC channels
reg i_sel = 0;
always @(posedge dsp_clk) i_sel <= dsp_reset ? 0 : ~i_sel;

genvar ch;
generate for (ch = 0; ch < N_ADC; ch = ch + 1) begin: gen_ddc
    assign adc[ch] = adc_data_in[(DW*ch)+:DW];

    ddc #(.DWI(DW), .DWO(DWBB), .DWLO(DWLO)) ddc (
        .clk    (dsp_clk),
        .reset  (dsp_reset),
        .adc    (adc[ch]),
        .cosa   (cosd),
        .sina   (sind),
        .i_sel  (i_sel),
        .i_out  (sig_i[ch]),
        .q_out  (sig_q[ch])
    );
end endgenerate

endmodule
