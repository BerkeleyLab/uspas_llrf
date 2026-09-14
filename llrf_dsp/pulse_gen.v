module pulse_gen #(
    parameter AW=12
) (
    input clk,
    input trigger,
    input [AW-1:0] start,
    input [AW-1:0] high_len,
    input [5:0] res,
    input stb_in,
    output pulse_last,
    output reg pulse_dval,
    output reg [AW:0] mod_ticks
);

reg [AW-1:0] end_val  = 0;
reg [AW:0]   pc       = 0;
reg          counting = 0;

always @(posedge clk) begin
    end_val <= start + high_len;
end

wire is_last     = (pc == end_val);
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

    if ((pc >> res) > 13'd4095)
        mod_ticks <= 13'd4095;
    else
        mod_ticks <= pc >> res;
end

assign pulse_last = counting && is_last;

endmodule
