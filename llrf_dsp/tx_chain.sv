// TX path (plan §2.2): the TX LO in the dac_clk domain, one DUC per drive
// (interpolation and domain crossing to dac_clk) and the DAC output select.
module tx_chain
    import llrf_shell_pkg::*;
(
    input              dsp_clk,
    input              dsp_reset,
    input  bb_t        drive_i [N_DRIVE],
    input  bb_t        drive_q [N_DRIVE],

    input              dac_clk,
    // TX LO and output select, dac_clk domain
    input  [17:0]      dds_amplitude,
    input  [18:0]      dds_phase_shift,
    input  [31:0]      dds_phase_step,
    input  [11:0]      dds_modulo,
    input              duc_spectral_flip,
    input              tx_afe_spectral_flip,
    input  [1:0]       dac_drive_sel,
    output [DW-1:0]    dac_data_a_out,
    output [DW-1:0]    dac_data_b_out
);

wire tx_dds_reset;
flag_xdomain dsp_reset_dac (
    .clk1         (dsp_clk),
    .flagin_clk1  (dsp_reset),
    .clk2         (dac_clk),
    .flagout_clk2 (tx_dds_reset)
);

wire signed [DWLO-1:0] duc_cos, duc_sin;
dds #(.DWLO(DWLO)) tx_dds (
    .clk          (dac_clk),
    .reset        (tx_dds_reset),
    .amplitude    (dds_amplitude),
    .phase_shift  (dds_phase_shift),
    .phase_step_h (dds_phase_step[31:12]),
    .phase_step_l (dds_phase_step[11:0]),
    .modulo       (dds_modulo),
    .cos_out      (duc_cos),
    .sin_out      (duc_sin)
);

wire signed [DW-1:0] dac_i_out [0:N_DRIVE-1];
wire signed [DW-1:0] dac_q_out [0:N_DRIVE-1];
genvar ch;
generate for (ch = 0; ch < N_DRIVE; ch = ch + 1) begin: gen_duc
    dac_duc #(
        .DWI    (DWBB),
        .DWO    (DW),
        .DWLO   (DWLO)
    ) duc (
        .dsp_clk        (dsp_clk),
        .dsp_reset      (dsp_reset),
        .spectral_flip  (duc_spectral_flip ^ tx_afe_spectral_flip),
        .i_data_in      (drive_i[ch]),
        .i_data_valid   (1'b1),
        .q_data_in      (drive_q[ch]),
        .q_data_valid   (1'b1),
        .dac_clk        (dac_clk),
        .cosa           (duc_cos),
        .sina           (duc_sin),
        .dac_i_out      (dac_i_out[ch]),
        .dac_q_out      (dac_q_out[ch])
    );
end endgenerate

// DAC output select, combinational: the zest ODDRs register it on dac_clk.
// (Was always @(dac_clk), which Vivado also built as combinational logic;
// only simulation saw it update on both edges.)
logic [DW-1:0] dac_data_a, dac_data_b;
always_comb begin
    case (dac_drive_sel)
        2'b00: begin    // loop 0 drives, I0Q0
            dac_data_a = dac_i_out[0];
            dac_data_b = dac_q_out[0];
        end
        2'b01: begin    // loop 1 drives, I1Q1
            dac_data_a = dac_i_out[1];
            dac_data_b = dac_q_out[1];
        end
        2'b10: begin    // dual loops I drive, I0I1
            dac_data_a = dac_i_out[0];
            dac_data_b = dac_i_out[1];
        end
        2'b11: begin    // dual loops Q drive, Q0Q1
            dac_data_a = dac_q_out[0];
            dac_data_b = dac_q_out[1];
        end
        default: begin
            dac_data_a = dac_i_out[0];
            dac_data_b = dac_q_out[0];
        end
    endcase
end
assign dac_data_a_out = dac_data_a;
assign dac_data_b_out = dac_data_b;

endmodule
