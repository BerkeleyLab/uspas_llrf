`timescale  1ns / 1ns
// Derived from bedrock/dsp/rot_dds.v
// Parameterized signal width; add phase offset

module dds #(
    parameter integer DWLO = 18,
    parameter [DWLO-1:0] LO_AMP = 74840,
    parameter [DWLO:0] PHS_OFF = 0
) (
	input clk,
	input reset,  // active high, synchronous with clk
	output signed [DWLO-1:0] sina,
	output signed [DWLO-1:0] cosa,
    input [DWLO:0] phase_shift,
    input [31:0] phase_step,    // {20'phase_step_h, 12'phase_step_l}
	input [11:0] modulo
);

    wire signed [DWLO-1:0] cosd, sind;
    wire [DWLO:0] phase_acc;
    ph_acc_general dds_lo (
        .clk            (clk),
        .reset          (reset),
        .phase_acc      (phase_acc),
        .phase_step_h   (phase_step[31:12]),
        .phase_step_l   (phase_step[11: 0]),
        .modulo         (modulo)
    );

    wire signed [DWLO:0] dds_phase = phase_acc + phase_shift - PHS_OFF;
    cordicg_b22 #(.nstg(20), .width(18)) dds (
        .clk            (clk),
        .opin           (2'b00),
        .xin            (LO_AMP),
        .yin            (18'd0),
        .phasein        (dds_phase),
        .xout           (cosa),
        .yout           (sina)
    );

endmodule
