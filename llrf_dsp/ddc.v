// Non-IQ Digital Down Converter
module ddc #(
    parameter integer DWI = 16,
    parameter integer DWO = 18,
    parameter integer DWLO = 18
) (
    input clk,
    input reset,

    input signed [DWI-1:0] adc,

    //LO signals from DDS
    input signed [DWLO-1:0] cosa,
    input signed [DWLO-1:0] sina,

    input  i_sel,
    output signed [DWO-1:0] i_out,
    output signed [DWO-1:0] q_out
);

// Washout filter, remove the DC component
// gain: (z-1) / (z*(z-(N-1)/N)), N=64
// delay: 2 cycles
// settling: ~70 cycles
wire signed [DWI-1:0] adc_filtered;
fwashout wash_filter (
    .clk    (clk),
    .rst    (reset),
    .track  (1'b1),
    .a_data (adc),
    .a_gate (1'b1),
    .a_trig (1'b0),
    .o_data (adc_filtered)
);

// Digital Downconverter
// Downconvert the IF field signal to get interleaved IQ signal
// gain: sin(2 * pi * theta)
// delay: 8 cycles
wire signed [DWO-2:0] iq;
noniq_ddc #(.DWO(DWO-1), .DWI(DWI), .DWLO(DWLO)) noniq_ddc (
    .clk    (clk),
    .cosd   (cosa),
    .sind   (sina),
    .a_data (adc_filtered),
    .i_sel  (i_sel),
    .o_data (iq)
);

// Interpolate downconverted field signals to get separate I&Q signals
// gain: 2
// delay: 3 cycles
fiq_interp #(.a_dw(DWO-1), .i_dw(DWO), .q_dw(DWO)) interp(
    .clk    (clk),
    .a_data (iq),
    .a_gate (1'b1),
    .a_trig (i_sel),
    .i_data (i_out),
    .q_data (q_out)
);

endmodule
