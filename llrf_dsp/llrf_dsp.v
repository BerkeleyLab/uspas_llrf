module llrf_dsp #(
    parameter integer KW = 18,
    parameter integer EW = 15,
    parameter integer DWI = 16,
    parameter [0:0] BASEBAND_INPUT = 0,   // select baseband input
    localparam integer DWO = 16,
    localparam integer DWLO = 18
) (
    // DSP clock
    input clk,
    input reset,

    // LO signals from DDS
    input signed [DWLO-1:0] cosa,
    input signed [DWLO-1:0] sina,

    input signed [DWI-1:0] adc_in,      // IF band input
    output signed [DWO-1:0] dac_out,    // IF band output

    input signed [KW-1:0] i_data_in,    // baseband input
    input signed [KW-1:0] q_data_in,    // baseband input

    output signed [KW-1:0] i_data_out,  // baseband output
    output signed [KW-1:0] q_data_out,  // baseband output

    input signed [DWLO:0] rx_phase_offset,
    input signed [DWLO:0] tx_phase_offset,

    output signed [KW-1:0] amp_measured,
    output signed [KW-1:0] phs_measured,

    input signed [KW-1:0] amp_setpoint,
    input signed [KW-1:0] phs_setpoint,

    input signed [KW-1:0] Kp_amp,
    input signed [KW-1:0] Kp_phs,
    input signed [KW-1:0] Ki_amp,
    input signed [KW-1:0] Ki_phs,
    input amp_loop_enable,
    input phs_loop_enable,
    input amp_loop_reset,
    input phs_loop_reset,
    output signed [EW-1:0] err_out_amp,
    output signed [EW-1:0] err_out_phs
);

    reg i_sel = 0;
    always @(posedge clk) i_sel <= ~i_sel;

    wire signed [KW-1:0] ddc_i_out, ddc_q_out;
    ddc #(.DWI(DWI), .DWO(KW), .DWLO(DWLO)) ddc (
        .clk              (clk),
        .reset            (reset),
        .adc              (adc_in),
        .cosa             (cosa),
        .sina             (sina),
        .i_sel            (i_sel),
        .i_out            (ddc_i_out),
        .q_out            (ddc_q_out)
    );

    wire signed [KW-1:0] field_i, field_q;
    assign field_i = BASEBAND_INPUT ? i_data_in : ddc_i_out;
    assign field_q = BASEBAND_INPUT ? q_data_in : ddc_q_out;

    wire signed [KW-1:0] drive_i, drive_q;
    dsp_core #(.KW(KW), .EW(EW)) feedback (
        .clk              (clk),
        .reset            (reset),
        .field_i          (field_i),
        .field_q          (field_q),
        .drive_i          (drive_i),
        .drive_q          (drive_q),
        .rx_phase_offset  (rx_phase_offset),
        .tx_phase_offset  (tx_phase_offset),
        .amp_measured     (amp_measured),
        .phs_measured     (phs_measured),
        .amp_setpoint     (amp_setpoint),
        .phs_setpoint     (phs_setpoint),
        .Kp_amp           (Kp_amp),
        .Kp_phs           (Kp_phs),
        .Ki_amp           (Ki_amp),
        .Ki_phs           (Ki_phs),
        .amp_loop_enable  (amp_loop_enable),
        .phs_loop_enable  (phs_loop_enable),
        .amp_loop_reset   (amp_loop_reset),
        .phs_loop_reset   (phs_loop_reset),
        .err_out_amp      (err_out_amp),
        .err_out_phs      (err_out_phs)
    );
    assign i_data_out = drive_i;
    assign q_data_out = drive_q;

    // Digital Up-converter - Double side-band modulator
    // Digital quadrature modulation followed by analog up-conversion mixer
    // rf_out = I*cos(wt) - Q*sin(wt)
    // delay: 3 cycles
    // XXX: cpxmul_fullspeed requires KW==DWLO
    cpxmul_fullspeed #(
        .DWI(KW), .OUT_SHIFT(DWO+1), .OWI(DWO)
    ) duc (
        .clk    (clk),
        .re_a   (drive_i),
        .im_a   (drive_q),
        .re_b   (cosa),
        .im_b   (sina),
        .re_out (dac_out)
    );

endmodule
