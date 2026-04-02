module pulse_gen #(
    parameter AW=12
) (
    input clk,
    input trigger,
    input [AW-1:0] start,
    input [AW-1:0] high_len,
    input stb_in,
    output pulse_last,
    output pulse_dval
);

reg [AW-1:0] len=0;
reg [AW:0] pc=0;
reg counting=0;
wire last = (pc==start+len);
always @(posedge clk) begin
    len <= high_len;
    if (last) counting <= 1'b0;
    else if (trigger) counting <= 1'b1;
    pc <= counting ? pc + stb_in : 0;
end

assign pulse_dval = counting && (pc >= start) && ~last;
assign pulse_last = last;
endmodule
