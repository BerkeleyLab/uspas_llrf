// Pulse generator. A trigger starts a count of stb_in strobes; pulse_dval is
// high while the count is in [start, start+high_len), and pulse_last flags the
// end of the pulse. pulse_idx = (count - start) >> res is registered with
// pulse_dval (valid while pulse_dval is high, 0 otherwise) and indexes
// per-pulse lookup tables, one entry per 2^res strobes.
module pulse_gen #(
    parameter AW=12,
    parameter RW=4
) (
    input clk,
    input trigger,
    input [AW-1:0] start,
    input [AW-1:0] high_len,
    input stb_in,
    input [RW-1:0] res,
    output pulse_last,
    output reg pulse_dval,
    output reg [AW-1:0] pulse_idx
);

// AW+1 bits, so start + high_len cannot wrap
reg [AW:0]   end_val = 0;
reg [AW:0]   pc      = 0;
reg          counting = 0;

always @(posedge clk) begin
    end_val <= start + high_len;
end

wire is_last = (pc == end_val);
wire is_at_start = (pc >= start);
wire in_pulse = counting && is_at_start && !is_last;
wire [AW:0] pc_rel = pc - start;

always @(posedge clk) begin
    if (is_last)
        counting <= 1'b0;
    else if (trigger)
        counting <= 1'b1;

    if (!counting && trigger)
        pc <= 0;
    else if (counting)
        pc <= pc + stb_in;
    else
        pc <= 0;
    pulse_dval <= in_pulse;
    pulse_idx  <= in_pulse ? pc_rel[AW-1:0] >> res : {AW{1'b0}};
end
assign  pulse_last = counting && is_last;
endmodule
