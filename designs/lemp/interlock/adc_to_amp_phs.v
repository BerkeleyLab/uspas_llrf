module adc_to_amp_phs #(
    parameter KW = 18
) (
    //DSP clock
    input clk,
    input reset,

    //RF ADC inputs, after downconverted to IF
    input signed [15:0] field,

    //LO signals from DDS
    input signed [17:0] cosa,
    input signed [17:0] sina,

    // Amplitude and phase
    output signed [17:0] amp,
    output signed [17:0] phs
);

// synchronize I/Q divider state for multiple DDC channels
reg i_sel = 0;
always @(posedge clk) i_sel <= ~i_sel;

wire signed [KW-1:0] field_i, field_q;
ddc #(.DWI(KW-2), .DWO(KW), .DWLO(KW)) ddc (
    .clk            (clk),
    .reset          (reset),
    .adc            (field),
    .cosa           (cosa),
    .sina           (sina),
    .i_sel          (i_sel),
    .i_out          (field_i),
    .q_out          (field_q)
);

// gain: 1.64676
// delay: 20 cycles
wire signed [KW-1:0] amp_measured_raw;
wire signed [KW:0] phs_measured_raw;
cordicg_b22 #(.nstg(20), .width(KW)) rx_cordic (
    .clk       (clk),
    .opin      (2'b01),
    .xin       (field_i),
    .yin       (field_q),
    .phasein   (19'b0),
    .xout      (amp_measured_raw),
    .phaseout  (phs_measured_raw)
);

// add the calculated amplitude as output
assign amp = amp_measured_raw;
assign phs = phs_measured_raw;

endmodule
