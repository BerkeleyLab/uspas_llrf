`timescale 1ns / 1ns
module ntw_analyzer #(
    parameter KW = 18  // signal width
) (
    input clk,
    input ext_amp_enable,                     // Enable amplitude network analyzer
    input ext_phs_enable,                     // Enable phase network analyzer
    input trig,                               // Waveform trigger, to synchronize

    input signed [KW-1:0] amp_setpoint,       // Incoming amplitude setpoint
    input signed [KW-1:0] phs_setpoint,       // Incoming phase setpoint

    input [17:0] lo_amp,                  // external; Amplitude level
    input [11:0] modulo,                  // external;
    input [31:0] phase_step_h,            // external;
    input [11:0] phase_step_l,            // external;

    output signed [KW-1:0] ntw_cos_debug,      // for debug only
    output signed [KW:0] ntw_phase_debug,      // for debug only
    output signed [KW-1:0] amp_stp_ntw,       // Final excited amplitude setpoint
    output signed [KW-1:0] phs_stp_ntw        // Final excited phase setpoint
);


// NCO Local Oscillator
// Phase accumulator
wire [18:0] phase;
ph_acc_alsu #(.dwi(12), .dwh(32)) ph_acc_ntw(.clk(clk), .reset(trig), .phase_acc(phase),
	.phase_step_h(phase_step_h), .phase_step_l(phase_step_l),
	.modulo(modulo)
);

// CORDIC to generate sin and cos from phase
wire signed [17:0] cosa, sina;
cordicg_b22 #(.width(18), .nstg(20), .def_op(0)) ntw_cordicg_b22 (
	.clk(clk), .opin(2'b00),
	.xin(lo_amp), .yin(18'd0), .phasein(phase),
	.xout(cosa), .yout(sina), .phaseout()
);

assign amp_stp_ntw = cosa + amp_setpoint;
assign phs_stp_ntw = cosa + phs_setpoint;

assign ntw_cos_debug = cosa;
assign ntw_phase_debug = phase;

endmodule
