// One feedback loop with pulse modulation (plan §1.2, step 5).
//
// A single pulse_gen counter gates the drive (pulse_mode) and indexes an
// amplitude and a phase modulation table (dpram, localbus port on lb_clk).
// While the pulse is on and idx < mod_len, the enabled table entries are added
// to the setpoints:
//   amp_sp = sat(amp_setpoint + amp_mod)       then the open-loop max clamp
//   phs_sp = phs_setpoint + phs_mod + phs_offset    (wraps)
// phs_offset is a design hook (0 in the base shell). The modulated setpoints
// follow pulse_idx/pulse_dval by 2 clocks: 1 for the table read, 1 output
// register. dsp_core closes the loop on field_i/q; err_amp/err_phs are exported
// for design hooks such as ALSU's phase_ramp.
module loop_ctrl #(
    parameter DWBB = 18,      // baseband width
    parameter EW = 15,        // dsp_core error width
    parameter PULSE_AW = 32,  // pulse counter width
    parameter MOD_AW = 14,    // modulation table depth 2^MOD_AW
    parameter RW = 4          // res_shift width
) (
    input dsp_clk,
    input dsp_reset,

    // pulse
    input trig,
    input [PULSE_AW-1:0] pulse_start,
    input [PULSE_AW-1:0] pulse_high_len,
    input [RW-1:0] res_shift,       // one table entry per 2^res_shift clocks
    input pulse_mode,               // 1: drive only while the pulse is on
    input drive_permit,             // drive enable and permits, from the shell

    // modulation
    input [MOD_AW:0] mod_len,       // table entries used, saturated to 2^MOD_AW
    input amp_mod_enable,
    input phs_mod_enable,
    input signed [DWBB-1:0] phs_offset,

    // loop configuration
    input signed [DWBB-1:0] amp_setpoint,
    input signed [DWBB-1:0] max_amp_setpoint,
    input signed [DWBB-1:0] phs_setpoint,
    input signed [DWBB-1:0] Kp_amp,
    input signed [DWBB-1:0] Kp_phs,
    input signed [DWBB-1:0] Ki_amp,
    input signed [DWBB-1:0] Ki_phs,
    input amp_loop_enable,
    input phs_loop_enable,
    input amp_loop_reset,
    input phs_loop_reset,
    input [DWBB:0] rx_phase_offset,
    input [DWBB:0] tx_phase_offset,

    // field in, drive out
    input signed [DWBB-1:0] field_i,
    input signed [DWBB-1:0] field_q,
    output signed [DWBB-1:0] drive_i,
    output signed [DWBB-1:0] drive_q,
    output drive_on,

    // status and design hooks
    output signed [DWBB-1:0] amp_measured,
    output signed [DWBB-1:0] phs_measured,
    output signed [EW-1:0] err_amp,
    output signed [EW-1:0] err_phs,
    output pulse_dval,
    output pulse_last,
    output [PULSE_AW-1:0] pulse_idx,
    output signed [DWBB-1:0] amp_setpoint_mod,  // setpoints after modulation
    output signed [DWBB-1:0] phs_setpoint_mod,  // (and clamp), into dsp_core

    // modulation table localbus port
    input lb_clk,
    input [MOD_AW-1:0] lb_addr,
    input [DWBB-1:0] lb_wdata,
    input lb_write_amp_mod,
    input lb_write_phs_mod,
    output [DWBB-1:0] lb_rdata_amp_mod,
    output [DWBB-1:0] lb_rdata_phs_mod
);

// ---------------------------------------------------------------------------
// Pulse counter: drive gate and modulation table index
// ---------------------------------------------------------------------------
pulse_gen #(.AW(PULSE_AW), .RW(RW)) pulse_gen (
    .clk        (dsp_clk),
    .trigger    (trig),
    .start      (pulse_start),
    .high_len   (pulse_high_len),
    .stb_in     (1'b1),
    .res        (res_shift),
    .pulse_last (pulse_last),
    .pulse_dval (pulse_dval),
    .pulse_idx  (pulse_idx)
);

// ---------------------------------------------------------------------------
// Modulation tables
// ---------------------------------------------------------------------------
localparam [MOD_AW:0] MOD_SIZE = 1 << MOD_AW;
wire [MOD_AW:0] mod_len_sat = (mod_len > MOD_SIZE) ? MOD_SIZE : mod_len;
wire in_mod = pulse_dval && (pulse_idx < mod_len_sat);

wire signed [DWBB-1:0] amp_mod, phs_mod;
dpram #(.aw(MOD_AW), .dw(DWBB)) amp_mod_ram (
    .clka (lb_clk), .addra (lb_addr), .dina (lb_wdata), .wena (lb_write_amp_mod),
    .douta (lb_rdata_amp_mod),
    .clkb (dsp_clk), .addrb (pulse_idx[MOD_AW-1:0]), .doutb (amp_mod)
);
dpram #(.aw(MOD_AW), .dw(DWBB)) phs_mod_ram (
    .clka (lb_clk), .addra (lb_addr), .dina (lb_wdata), .wena (lb_write_phs_mod),
    .douta (lb_rdata_phs_mod),
    .clkb (dsp_clk), .addrb (pulse_idx[MOD_AW-1:0]), .doutb (phs_mod)
);

// gates, aligned with the table read data (1 clock after the index)
reg amp_mod_gate = 1'b0, phs_mod_gate = 1'b0;
always @(posedge dsp_clk) begin
    amp_mod_gate <= in_mod && amp_mod_enable;
    phs_mod_gate <= in_mod && phs_mod_enable;
end

// ---------------------------------------------------------------------------
// Modulated setpoints
// ---------------------------------------------------------------------------
localparam signed [DWBB-1:0] SAT_MAX = {1'b0, {(DWBB-1){1'b1}}};
localparam signed [DWBB-1:0] SAT_MIN = {1'b1, {(DWBB-1){1'b0}}};
localparam signed [DWBB-1:0] ZERO = 0;  // keeps the conditionals below signed

wire signed [DWBB:0] amp_sum = amp_setpoint + (amp_mod_gate ? amp_mod : ZERO);
wire signed [DWBB-1:0] amp_sat = (amp_sum > SAT_MAX) ? SAT_MAX :
                                 (amp_sum < SAT_MIN) ? SAT_MIN : amp_sum[DWBB-1:0];
// open loop: clamp to max_amp_setpoint to avoid DAC saturation;
// closed loop: the setpoint is compared with the measurement, no clamp
wire signed [DWBB-1:0] amp_clamped = amp_loop_enable ? amp_sat :
    (amp_sat > max_amp_setpoint ? max_amp_setpoint : amp_sat);
wire signed [DWBB-1:0] phs_sum = phs_setpoint + (phs_mod_gate ? phs_mod : ZERO) + phs_offset;

reg signed [DWBB-1:0] amp_sp = 0, phs_sp = 0;
always @(posedge dsp_clk) begin
    amp_sp <= amp_clamped;
    phs_sp <= phs_sum;
end
assign amp_setpoint_mod = amp_sp;
assign phs_setpoint_mod = phs_sp;

// ---------------------------------------------------------------------------
// Feedback controller in baseband
// ---------------------------------------------------------------------------
wire signed [DWBB-1:0] drive_i_ctl, drive_q_ctl;
dsp_core #(.KW(DWBB), .EW(EW)) feedback (
    .clk              (dsp_clk),
    .reset            (dsp_reset),
    .field_i          (field_i),
    .field_q          (field_q),
    .drive_i          (drive_i_ctl),
    .drive_q          (drive_q_ctl),
    .rx_phase_offset  (rx_phase_offset),
    .tx_phase_offset  (tx_phase_offset),
    .amp_measured     (amp_measured),
    .phs_measured     (phs_measured),
    .amp_setpoint     (amp_sp),
    .phs_setpoint     (phs_sp),
    .Kp_amp           (Kp_amp),
    .Kp_phs           (Kp_phs),
    .Ki_amp           (Ki_amp),
    .Ki_phs           (Ki_phs),
    .amp_loop_enable  (amp_loop_enable),
    .phs_loop_enable  (phs_loop_enable),
    .amp_loop_reset   (amp_loop_reset),
    .phs_loop_reset   (phs_loop_reset),
    .err_out_amp      (err_amp),
    .err_out_phs      (err_phs)
);

// drive gate: modulation is independent of pulse_mode (P7)
assign drive_on = drive_permit && (pulse_mode ? pulse_dval : 1'b1);
assign drive_i = drive_on ? drive_i_ctl : ZERO;
assign drive_q = drive_on ? drive_q_ctl : ZERO;

endmodule
