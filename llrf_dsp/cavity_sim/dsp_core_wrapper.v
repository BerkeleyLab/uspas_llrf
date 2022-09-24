`timescale 1ns / 1ps
`include "settings.vams"
module dsp_core_wrapper #(
    parameter KW = 18,
    parameter EW = 15
) (
    //DSP clock
    input clk,
    input reset,

    //RF ADC inputs, after downconverted to IF
    input signed [15:0] cav_field,
    input signed [15:0] cav_fwd,
    input signed [15:0] cav_rev,
    input signed [15:0] cav_phr,

    //DAC upconverted signal
    output signed [15:0] dac_out,

    //Amp/phs setpoints
    input signed [17:0] amp_setpoint,
    input signed [17:0] phs_setpoint,

    //dds parameters
    input [31:0] dds_phase_step,
    input [18:0] dds_phase_shift,
    input [11:0] dds_modulo,

    //PI Loop
    input signed [KW-1:0] Kp_amp,
    input signed [KW-1:0] Kp_phs,
    input signed [KW-1:0] Ki_amp,
    input signed [KW-1:0] Ki_phs,
    input loop_control,
    input loop_reset,

    output signed [17:0] amp_measured_debug,
    output signed [17:0] phs_measured_debug
);

assign amp_measured_debug = dut.amp_measured;
assign phs_measured_debug = dut.phs_measured;

wire signed [17:0] cosd, sind;
wire [18:0] dds_phase_acc;
ph_acc dds_lo (
    .clk            (clk),
    .reset          (1'b0),
    .en             (1'b1),
    .phase_acc      (dds_phase_acc),
    .phase_step_h   (dds_phase_step[31:12]),
    .phase_step_l   (dds_phase_step[11:0]),
    .modulo         (dds_modulo)
);

cordicg_b22 #(.nstg(20), .width(18)) dds_cordicg_i(
    .clk    (clk),
    .opin   (2'b00),
    .xin    (18'd`LO_AMP),
    .yin    (18'd0),
    .phasein(dds_phase_acc + dds_phase_shift),
    .xout   (cosd),
    .yout   (sind)
);


dsp_core #(.KW(18)) dut (
    .clk                (clk),
    .reset              (reset),
    .cav_field          (cav_field),
    .cosa               (cosd),
    .sina               (sind),
    .dac_out            (dac_out),
    .amp_setpoint       (amp_setpoint),
    .phs_setpoint       (phs_setpoint),
    .Kp_amp             (Kp_amp),
    .Kp_phs             (Kp_phs),
    .Ki_amp             (Ki_amp),
    .Ki_phs             (Ki_phs),
    .amp_loop_reset     (loop_reset),
    .phs_loop_reset     (loop_reset),
    .amp_loop_enable    (loop_control),
    .phs_loop_enable    (loop_control)
);
endmodule
