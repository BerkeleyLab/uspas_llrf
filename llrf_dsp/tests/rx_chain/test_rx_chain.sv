// rx_chain with LEMP's DC channels (ADC 6 and 7), arrays flattened for cocotb
module test_rx_chain
    import llrf_shell_pkg::*;
(
    input                    dsp_clk,
    input                    dsp_reset,
    input  [DW*N_ADC-1:0]    adc_data_in,
    input  [17:0]            dds_amplitude,
    input  [18:0]            dds_phase_shift,
    input  [31:0]            dds_phase_step,
    input  [11:0]            dds_modulo,
    output [DWBB*N_ADC-1:0]  sig_i_flat,
    output [DWBB*N_ADC-1:0]  sig_q_flat,
    output [DWBB*N_ADC-1:0]  mon_i_flat,
    output [DWBB*N_ADC-1:0]  mon_q_flat,
    output [DWLO-1:0]        lo_cos,
    output [DWLO-1:0]        lo_sin
);
localparam logic [N_ADC-1:0] DC_CH_MASK = 8'b1100_0000;

adc_t adc [N_ADC];
bb_t sig_i [N_ADC], sig_q [N_ADC], mon_i [N_ADC], mon_q [N_ADC];
rx_chain #(.DC_CH_MASK(DC_CH_MASK)) dut (
    .dsp_clk         (dsp_clk),
    .dsp_reset       (dsp_reset),
    .adc_data_in     (adc_data_in),
    .dds_amplitude   (dds_amplitude),
    .dds_phase_shift (dds_phase_shift),
    .dds_phase_step  (dds_phase_step),
    .dds_modulo      (dds_modulo),
    .adc             (adc),
    .sig_i           (sig_i),
    .sig_q           (sig_q),
    .mon_i           (mon_i),
    .mon_q           (mon_q),
    .lo_cos          (lo_cos),
    .lo_sin          (lo_sin)
);

genvar ch;
generate for (ch = 0; ch < N_ADC; ch = ch + 1) begin: gen_flat
    assign sig_i_flat[DWBB*ch+:DWBB] = sig_i[ch];
    assign sig_q_flat[DWBB*ch+:DWBB] = sig_q[ch];
    assign mon_i_flat[DWBB*ch+:DWBB] = mon_i[ch];
    assign mon_q_flat[DWBB*ch+:DWBB] = mon_q[ch];
end endgenerate
endmodule
