module zest_dac_interp #(
    parameter integer DW=14
) (
    input dsp_clk,
    input [DW-1:0] data_dsp_in,
    input [DW-1:0] coeff,
    input dac_clk,
    output [DW-1:0] data_dac_out
);
    // dac_clk is 2x of dsp_clk, phase aligned
    (* ASYNC_REG = "TRUE" *) reg signed [DW-1:0] d0=0, d1=0;
    always @(posedge dac_clk) begin
        d0 <= data_dsp_in;
        d1 <= d0;
    end

    reg signed [2*DW:0] r=0;
    reg signed [DW-1:0] d2=0, r1=0;
    wire signed [DW:0] sum = d2 + d1;
    always @(posedge dac_clk) begin
        d2 <= d1;
        r <= sum * coeff;
        r1 <= r >>> DW;
    end
    assign data_dac_out = r1;

endmodule