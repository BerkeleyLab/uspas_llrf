
module adc_buf #(
    parameter integer AW=12,
    parameter integer DW=16,
    localparam integer WFM_LEN=(2**AW)
) (
    // adc_clk domain
    input           adc_trigger, // single cycle
    input           adc_phy_clk,
    input           adc_phy_val,
    input [DW-1:0]  adc_phy_dat,
    // lb_clk domain
    input           lb_clk,
    input           lb_read,
    input           lb_rvalid,
    input [AW-1:0]  lb_addr,
    output [DW-1:0] lb_rdata
);

reg counting=0;
reg [AW-1:0] pc=0;

// generate read pc from adc_clk domain
always @(posedge adc_phy_clk) begin
    if (pc==WFM_LEN-1) counting <= 0;
    else if (adc_trigger) counting <= 1'b1;
    pc <= counting ? pc + adc_phy_val : 0;
end

dpram #(
    .dw(DW),
    .aw(AW)
) dpram_0 (
    .clka   (adc_phy_clk    ),
    .addra  (pc             ),
    .dina   (adc_phy_dat    ),
    .wena   (counting       ),
    .clkb   (lb_clk         ),
    .addrb  (lb_addr        ),
    .doutb  (lb_rdata       )
);
endmodule
