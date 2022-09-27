module udp_rgmii #(
    parameter IP ={8'd192, 8'd168, 8'd19, 8'd122},
    parameter MAC = 48'h00105ad155b2,
    parameter LB_READ_DELAY = 3
) (
	output [3:0]    RGMII_TXD,
	output          RGMII_TX_CTRL,
	output          RGMII_TX_CLK,
	input [3:0]     RGMII_RXD,
	input           RGMII_RX_CTRL,
	input           RGMII_RX_CLK,
	output          PHY_RSTN,

    input           clk_locked,
    input           gmii_tx_clk,
    input           gmii_tx_clk90,
    output          gmii_rx_clk,

    // lb master
    output          lb_clk,
    output [23:0]   lb_addr,
    output          lb_write,
    output          lb_read,
    output [31:0]   lb_wdata,
    input  [31:0]   lb_rdata,
    output          lb_rvalid,

    // Mac control
	input           host_clk,
	input [10:0]    host_waddr,
	input           host_write,
	input [15:0]    host_wdata,
	output          tx_mac_done,
    // diagnostics
    output [7:0]    mac_status
);

// Keep the PHY's reset pin low for the first 33 ms
reg [26:0] rx_heartbeat=0, tx_heartbeat=0;
always @(posedge gmii_rx_clk) rx_heartbeat <= rx_heartbeat+1;
always @(posedge gmii_tx_clk) tx_heartbeat <= tx_heartbeat+1;
reg phy_rb=0;
always @(posedge gmii_tx_clk) begin
	if (tx_heartbeat[21]) phy_rb <= 1;
	if (~clk_locked) phy_rb <= 0;
end
assign PHY_RSTN = phy_rb;

wire [7:0] gmii_txd, gmii_rxd;
wire gmii_tx_en, gmii_tx_er, gmii_rx_dv, gmii_rx_er;
gmii_to_rgmii #( .in_phase_tx_clk(1)) gmii_to_rgmii_i (
	.rgmii_txd      (RGMII_TXD),
	.rgmii_tx_ctl   (RGMII_TX_CTRL),
	.rgmii_tx_clk   (RGMII_TX_CLK),
	.rgmii_rxd      (RGMII_RXD),
	.rgmii_rx_ctl   (RGMII_RX_CTRL),
	.rgmii_rx_clk   (RGMII_RX_CLK),
	.gmii_tx_clk    (gmii_tx_clk),
	.gmii_tx_clk90  (gmii_tx_clk90),
	.gmii_txd       (gmii_txd),
	.gmii_tx_en     (gmii_tx_en),
	.gmii_tx_er     (gmii_tx_er),
	.gmii_rxd       (gmii_rxd),
	.gmii_rx_clk    (gmii_rx_clk),
	.gmii_rx_dv     (gmii_rx_dv),
	.gmii_rx_er     (gmii_rx_er)
);

// localbus master
wire rx_mon;
wire tx_mon;
wire tx_mac_done;

rtefi_blob #(
    .ip(IP), .mac(MAC), .p3_read_pipe_len(LB_READ_DELAY)
) ether_gmii_i (
    .tx_clk         (gmii_tx_clk),
    .rx_clk         (gmii_rx_clk),
    .rxd            (gmii_rxd),
    .rx_dv          (gmii_rx_dv),
    .rx_er          (gmii_rx_er),
    .txd            (gmii_txd),
    .tx_en          (gmii_tx_en),
    .tx_er          (gmii_tx_er),

    .enable_rx      (1'b1),
    .config_clk     (gmii_tx_clk),
    .config_a       (4'h0),
    .config_d       (8'h0),
    .config_s       (1'h0),  // MAC/IP address write
    .config_p       (1'h0),  // UDP port number write
    .p2_nomangle    (1'h0),

	.host_raddr     (),
	.host_rdata     (16'h0),
    .buf_start_addr (10'h0),
    .tx_mac_start   (1'b0),
    .rx_mac_hbank   (1'b0),
    .rx_mac_accept  (1'b0),
    .tx_mac_done    (tx_mac_done),

    .p3_lb_clk      (lb_clk),
    .p3_lb_addr     (lb_addr),
    .p3_lb_write    (lb_write),
    .p3_lb_read     (lb_read),
    .p3_lb_rvalid   (lb_rvalid),
    .p3_lb_wdata    (lb_wdata),
    .p3_lb_rdata    (lb_rdata),
    .rx_mon         (rx_mon),
    .tx_mon         (tx_mon)
);
assign mac_status = {4'h0, tx_heartbeat[26], rx_heartbeat[26], tx_mon, rx_mon};
endmodule
