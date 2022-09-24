module dsp_core #(
    parameter KW = 18,
    parameter EW = 15
) (
    //DSP clock
    input clk,
    input reset,

    //RF ADC inputs, after downconverted to IF
    input signed [15:0] cav_field,

    //LO signals from DDS
    input signed [17:0] cosa,
    input signed [17:0] sina,

    //DAC upconverted signal
    output signed [15:0] dac_out,

    input signed [17:0] amp_setpoint,
    input signed [17:0] phs_setpoint,

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

// Washout filter,remove the DC component before down-conversion
wire signed [15:0] cav_field_filtered;
fwashout wash_filter (
    .clk    (clk),
    .rst    (reset),
    .track  (1'b1),
    .a_data (cav_field),
    .a_gate (1'b1),
    .a_trig (1'b0),
    .o_data (cav_field_filtered)
);

// Digital Downconverter
// Downconvert the IF field signal to get interleaved IQ signal
wire i_sel;
wire signed [KW-2:0] field_iq;
fdownconvert_als #(.ODW(KW-1)) dut(
    .clk    (clk),
    .cosd   (cosa),
    .sind   (sina),
    .a_data (cav_field_filtered),
    .i_sel  (i_sel),
    .o_data (field_iq)
);

// Interpolate downconverted field signals to get separate I&Q signals
wire signed [KW-1:0] field_i, field_q;
fiq_interp #(.a_dw(KW-1), .i_dw(KW), .q_dw(KW)) interp(
    .clk    (clk),
    .a_data (field_iq),
    .a_gate (1'b1),
    .a_trig (i_sel),
    .i_data (field_i),
    .q_data (field_q)
);

// Up stream total:
// Amp Gain = 2.9337  @ 4/11
// Phs Gain = 130 deg @ 4/11
wire signed [KW-1:0] amp_measured_raw;
wire signed [KW:0] phs_measured_raw;
cordicg_b22 #(.nstg(20), .width(KW)) rx_cordic (
    .clk       (clk),
    .opin      (2'b01),
    .xin       (field_i),
    .yin       (field_q),
    .phasein   (19'h0),
    .xout      (amp_measured_raw),
    .phaseout  (phs_measured_raw)
);

// Amp/Phs PI loop
wire signed [KW-1:0] amp_measured = amp_measured_raw;
// compensate measured 130 deg Rx phase gain
wire signed [KW-1:0] phs_measured = phs_measured_raw[KW:1] - 18'd94663 - 18'd29768;

wire signed [KW-1:0] drive_amp;
pi_scalar #(.KW(KW), .EW(EW), .WRAP(0)) pi_amp (
    .clk        (clk),
    .reset      (amp_loop_reset),
    .enable     (amp_loop_enable),
    .Kp         (Kp_amp),
    .Ki         (Ki_amp),
    .setpoint   (amp_setpoint),
    .measured   (amp_measured),
    .err_out    (err_out_amp),
    .drive      (drive_amp)
);

wire signed [KW-1:0] drive_phs;
pi_scalar #(.KW(KW), .EW(EW), .WRAP(1)) pi_phs (
    .clk        (clk),
    .reset      (phs_loop_reset),
    .enable     (phs_loop_enable),
    .Kp         (Kp_phs),
    .Ki         (Ki_phs),
    .setpoint   (phs_setpoint + 18'd73),  // cancel 0.1 deg phase gain
    .measured   (phs_measured),
    .err_out    (err_out_phs),
    .drive      (drive_phs)
);

wire signed [KW-1:0] drive_i;
wire signed [KW-1:0] drive_q;

// compensate measured 49.19 deg phase gain, plus 40.9 deg lo shift
wire signed [KW:0] phasein = {drive_phs, 1'b0} - 19'd71652 - 19'd59565;
cordicg_b22 #(.nstg(20), .width(KW)) tx_cordic (
    .clk        (clk),
    .opin       (2'b00),
    .xin        (drive_amp),
    .yin        (18'h0),
    .phasein    (phasein),
    .xout       (drive_i),
    .yout       (drive_q)
);

// Digital Up-converter - Double side-band modulator
// check out pg. 268 from https://cds.cern.ch/record/1100538/files/p249.pdf
// Digital quadrature modulation followed by analog up-conversion mixer
// rf_out = I*cos(wt) + Q*sin(wt)
// Gain = `LO_AMP * `CORDIC_GAIN / 2**18 / 2 = 0.235068
flevel_set upconvert (
    .clk    (clk),
    .cosd   (cosa),
    .sind   (sina),
    .i_data (drive_i[KW-1:KW-17]),
    .i_gate (1'b1),
    .i_trig (1'b1),
    .q_data (drive_q[KW-1:KW-17]),
    .q_gate (1'b1),
    .q_trig (1'b1),
    .o_data (dac_out)
);

endmodule
