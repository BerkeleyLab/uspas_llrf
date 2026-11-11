// Calculate magnitude of signals from baseband I/Q signals
// 3 series 2nd-order CIC filters for Turn-by-Turn, Fast Acquisition, and Slow Acquisition
module cic_mag3 #(
    parameter integer DW   = 16,
    parameter integer EX0  = 5,
    parameter integer EX1  = 8,
    parameter integer EX2  = 10
) (
    input wire clk,
    input wire signed [DW-1:0] sig_i,
    input wire signed [DW-1:0] sig_q,
    input wire sig_valid,
    output wire [3*DW-1:0] sig_cic_mag,
    output wire [2:0] sig_cic_mag_valid
);

// Full speed CORDIC magnitude detector
wire signed [DW-1:0] sig_amp;
wire signed [DW:0] sig_phs;

cordicg_b22 #(.nstg(20), .width(DW)) cordic_detect (
    .clk        (clk),
    .opin       (2'b01),
    .xin        (sig_i),
    .yin        (sig_q),
    .phasein    (17'b0),
    .xout       (sig_amp),
    .phaseout   (sig_phs)
);

wire sig_amp_valid;
reg_delay #(.dw(1), .len(22)) delay0 (
    .clk        (clk),
    .reset      (1'b0),
    .gate       (1'b1),
    .din        (sig_valid),
    .dout       (sig_amp_valid)
);

// 3 Series (cascaded) 2nd-order CIC filter decimators:
// Stage 0 (TbT): fed by sig_amp and sig_amp_valid
// Stage 1 (FA) : fed by Stage 0 output and data_out_gate
// Stage 2 (SA) : fed by Stage 1 output and data_out_gate
wire signed [DW-1:0] cic_in [0:2];
wire                 cic_in_gate [0:2];
wire signed [DW-1:0] cic_out [0:2];
wire                 cic_out_gate [0:2];

assign cic_in[0] = sig_amp;
assign cic_in_gate[0] = sig_amp_valid;

assign cic_in[1] = cic_out[0];
assign cic_in_gate[1] = cic_out_gate[0];

assign cic_in[2] = cic_out[1];
assign cic_in_gate[2] = cic_out_gate[1];

genvar i;
generate
    for (i = 0; i < 3; i = i + 1) begin: gen_cic
        localparam integer EX = (i == 0) ? EX0 :
                                (i == 1) ? EX1 : EX2;

        cic_simple2 #(
            .DW         (DW),
            .EX         (EX),
            .EXT_ROLL   (0)
        ) cic_simple2_inst (
            .clk            (clk),
            .reset          (1'b0),
            .data_in        (cic_in[i]),
            .data_in_gate   (cic_in_gate[i]),
            .roll           (1'b0),
            .data_out       (cic_out[i]),
            .data_out_gate  (cic_out_gate[i])
        );

        assign sig_cic_mag[i*DW +: DW] = cic_out[i];
        assign sig_cic_mag_valid[i]    = cic_out_gate[i];
    end
endgenerate

endmodule