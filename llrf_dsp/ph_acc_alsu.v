`timescale 1ns / 1ns
module ph_acc_alsu #(
   parameter dwi = 12,
   parameter dwh = 20
)(
	input clk,  // Rising edge clock input; all logic is synchronous in this domain
	input reset,  // Active high, synchronous with clk
	output [18:0] phase_acc,  // Output phase word
	input [dwh-1:0] phase_step_h,  // High order (coarse, binary) phase step
	input [dwi-1:0] phase_step_l,  // Low order (fine, possibly non-binary) phase step
	input [dwi-1:0] modulo  // Encoding of non-binary modulus; 0 means binary
);

reg carry=0, reset1=0;
reg [dwh-1:0] phase_h=0, phase_step_hp=0;
reg [dwi-1:0] phase_l=0;
always @(posedge clk) begin
	{carry, phase_l} <= reset ? 13'b0 : ((carry ? modulo : 12'b0) + phase_l + phase_step_l);
	phase_step_hp <= phase_step_h;
	reset1 <= reset;
	phase_h <= reset1 ? 20'b0 : (phase_h + phase_step_hp + carry);
end
assign phase_acc=phase_h[dwh-1:dwh-1-18];

endmodule
