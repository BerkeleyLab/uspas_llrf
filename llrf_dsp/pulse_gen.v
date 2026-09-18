module pulse_gen #(
    parameter AW=12
) (
    input clk,
    input trigger,
    input [AW-1:0] start,
    input [AW-1:0] high_len,
    input stb_in,
    output pulse_last,
    output reg pulse_dval
);

reg [AW-1:0] end_val = 0;
reg [AW:0]   pc      = 0;
reg          counting = 0;

always @(posedge clk) begin
    end_val <= start + high_len;
end

wire is_last = (pc == end_val);
wire is_at_start = (pc >= start);

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
    pulse_dval <= counting && is_at_start && !is_last;
end
assign  pulse_last = counting && is_last;
endmodule
