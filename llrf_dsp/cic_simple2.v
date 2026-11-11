// Second-order Cascaded Integrator-Comb (CIC) decimation filter (N=2, M=1)
//
// Implements 2 integrator stages at input sampling rate followed by
// decimation by R = 2^EX and 2 comb (differentiator) stages at decimated rate.
// Configured with signed input and output.
//
// Transfer function: H(z) = ((1 - z^(-R)) / (1 - z^(-1)))^2
// DC Gain: R^2 = 2^(2*EX)
// Bit truncation diff2[DW+2*EX-1 : 2*EX] normalizes DC gain to 1.0.

`timescale 1ns / 1ns

module cic_simple2 #(
    parameter integer DW       = 16,   // Input and output data width
    parameter integer EX       = 4,    // Decimation factor R = 2^EX
    parameter integer EXT_ROLL = 0     // 1: use external roll strobe; 0: internal counter
) (
    input  wire                 clk,
    input  wire                 reset,
    input  wire signed [DW-1:0] data_in,
    input  wire                 data_in_gate,
    input  wire                 roll,          // External decimation strobe (when EXT_ROLL=1)
    output wire signed [DW-1:0] data_out,
    output wire                 data_out_gate
);

    localparam integer ACC_WIDTH = DW + 2 * EX;

    // ------------------------------------------------------------------------
    // Integrator Stages (running at input rate, gated by data_in_gate)
    // ------------------------------------------------------------------------
    reg signed [ACC_WIDTH-1:0] int1 = 0;
    reg signed [ACC_WIDTH-1:0] int2 = 0;
    reg [EX-1:0]               div = 0;
    reg                        iroll = 0;
    reg                        roll_r = 0;

    always @(posedge clk) begin
        if (reset) begin
            int1   <= 0;
            int2   <= 0;
            div    <= 0;
            iroll  <= 0;
            roll_r <= 0;
        end else if (data_in_gate) begin
            int1   <= int1 + data_in;
            int2   <= int2 + int1;
            {iroll, div} <= div + 1'b1;
            roll_r <= roll;
        end
    end

    wire uroll = EXT_ROLL ? roll_r : iroll;

    // ------------------------------------------------------------------------
    // Comb / Differentiator Stages (running at decimated rate)
    // ------------------------------------------------------------------------
    reg signed [ACC_WIDTH-1:0] int2_d1 = 0;
    reg signed [ACC_WIDTH-1:0] diff1 = 0;
    reg signed [ACC_WIDTH-1:0] diff2 = 0;

    reg data_in_gate_d = 0;
    reg comb_gate = 0;
    reg comb_gate_d = 0;

    always @(posedge clk) begin
        if (reset) begin
            data_in_gate_d <= 0;
            comb_gate      <= 0;
            comb_gate_d    <= 0;
            int2_d1        <= 0;
            diff1          <= 0;
            diff2          <= 0;
        end else begin
            data_in_gate_d <= data_in_gate;
            comb_gate      <= data_in_gate_d & uroll;
            comb_gate_d    <= comb_gate;

            if (comb_gate) begin
                // Comb stage 1: diff1 stores y1[k-1]
                int2_d1 <= int2;
                diff1   <= int2 - int2_d1;
                // Comb stage 2: diff2 calculates y1[k] - y1[k-1]
                diff2   <= (int2 - int2_d1) - diff1;
            end
        end
    end

    assign data_out_gate = comb_gate_d;
    assign data_out      = diff2[ACC_WIDTH-1 : 2*EX];

endmodule
