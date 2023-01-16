
module adc_buf #(
    parameter AW=12,
    parameter DW=16
) (
    // adc_clk domain
    input           adc_trigger, // single cycle
    input [AW-1:0]  wfm_len,
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
wire wfm_last = (pc==wfm_len);

// generate read pc from adc_clk domain
always @(posedge adc_phy_clk) begin
    if (wfm_last) counting <= 0;
    else if (adc_trigger) counting <= 1'b1;
    pc <= counting ? pc + adc_phy_val : 0;
end
wire buf_in_dval = counting;

// Atomic flip between banks
// No flip when reading or writing
reg wbank=0;
wire flip_cmd;
reg flip_rqst=0;
wire flip_ok = flip_rqst & ~counting & ~lb_read;
always @(posedge adc_phy_clk) begin
	if (flip_ok) begin
		wbank <= ~wbank;
		flip_rqst <= 0;
    end else if (flip_cmd) begin
        flip_rqst <= 1'b1;  // read done, want to flip
    end
end

// lb_clk domain, 1 cycle
wire read_last = (lb_addr==wfm_last) & lb_read & lb_rvalid;
flag_xdomain flip_bank(
    .clk1           (lb_clk),
    .flagin_clk1    (read_last),
    .clk2           (adc_phy_clk),
    .flagout_clk2   (flip_cmd)
);

dpram #(
    .dw(DW),
    .aw(AW+1)
) dpram_0 (
    .clka   (adc_phy_clk    ),
    .addra  ({wbank, pc}   ),
    .dina   (adc_phy_dat    ),
    .wena   (buf_in_dval    ),
    .clkb   (lb_clk         ),
    .addrb  ({~wbank,lb_addr}),
    .doutb  (lb_rdata   )
);
endmodule
