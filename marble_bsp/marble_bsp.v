module marble_bsp #(
    parameter IP ={8'd192, 8'd168, 8'd19, 8'd122},
    parameter MAC = 48'h00105ad155b2,
    parameter LB_READ_DELAY = 3,
    parameter DEFAULT_ENABLE_RX = 1
) (
    // RGMII
    output [3:0]    RGMII_TXD,
    output          RGMII_TX_CTRL,
    output          RGMII_TX_CLK,
    input [3:0]     RGMII_RXD,
    input           RGMII_RX_CTRL,
    input           RGMII_RX_CLK,
    output          PHY_RSTN,

    // Mailbox SPI
    input           FPGA_SCK,
    input           FPGA_CSB,
    input           FPGA_PICO,
    output          FPGA_POCI,

    // Clocks
    input           clk_locked,
    input           gmii_tx_clk,
    input           gmii_tx_clk90,
    output          gmii_rx_clk,

    // lb controller
    output          m_lb_clk,
    output [23:0]   m_lb_addr,
    output          m_lb_write,
    output          m_lb_read,
    output [31:0]   m_lb_wdata,
    input  [31:0]   m_lb_rdata,
    output          m_lb_rvalid,
    output          m_lb_prefill,

    // lb peripheral
    input           lb_clk,
    input [17:0]    lb_addr,
    input           lb_write,
    input           lb_read,
    input           lb_rvalid,
    input [31:0]    lb_wdata,
    output [31:0]   lb_rdata,

    // diagnostics
    output [7:0]    mac_status
);

wire enable_rx;
wire config_s, config_p;
wire [7:0] config_a, config_d;
wire [7:0] mbox_out;

mmc_mailbox #(
    .DEFAULT_ENABLE_RX(DEFAULT_ENABLE_RX)
) mailbox_i (
    .clk                (lb_clk),  // input
    // localbus mailbox memory interface
    .lb_addr            (lb_addr[10:0]), // input [10:0]
    .lb_din             (lb_wdata[7:0]), // input [7:0]
    .lb_dout            (mbox_out),      // output [7:0]
    .lb_write           (lb_write), // input
    .lb_control_strobe  (lb_read),  // input
    // SPI PHY
    .sck                (FPGA_SCK),     // input
    .ncs                (FPGA_CSB),     // input
    .pico               (FPGA_PICO),    // input
    .poci               (FPGA_POCI),    // output
    // Config pins for badger (rtefi) interface
    .config_s           (config_s),     // output
    .config_p           (config_p),     // output
    .config_a           (config_a),     // output [7:0]
    .config_d           (config_d),     // output [7:0]
    // Special pins
    .enable_rx          (enable_rx),    // output
    .spi_pins_debug     () // {MISO, din, sclk_d1, csb_d1};
);

reg [31:0] lb_rdata_r=0;
wire [3:0] lb_addr_mux = lb_addr[12+:4];

always @(*) begin
    case(lb_addr_mux)
    4'h0: lb_rdata_r = {24'h0, mbox_out};
    4'h1: lb_rdata_r = {24'h0, mac_status};
    default: lb_rdata_r = 32'hdeaddead;
    endcase
end
assign lb_rdata = lb_rdata_r;

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
    .gmii_rx_er     (gmii_rx_er),
    .clk_div        (1'b0),
    .idelay_ce      (1'b0),
    .idelay_value_in(5'b0)
);

// localbus master
wire rx_mon;
wire tx_mon;

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

    .enable_rx      (enable_rx),
    .config_clk     (gmii_tx_clk),
    .config_a       (config_a[3:0]),  // input [3:0]
    .config_d       (config_d),  // input [7:0]
    .config_s       (config_s),  // MAC/IP address write
    .config_p       (config_p),  // UDP port number write
    .p2_nomangle    (1'h0),

    .host_raddr     (),
    .host_rdata     (16'h0),
    .buf_start_addr (10'h0),
    .tx_mac_start   (1'b0),
    .rx_mac_hbank   (1'b0),
    .rx_mac_accept  (1'b0),
    .tx_mac_done    (),

    .p3_lb_clk      (m_lb_clk),
    .p3_lb_addr     (m_lb_addr),
    .p3_lb_write    (m_lb_write),
    .p3_lb_read     (m_lb_read),
    .p3_lb_rvalid   (m_lb_rvalid),
    .p3_lb_wdata    (m_lb_wdata),
    .p3_lb_rdata    (m_lb_rdata),
    .p3_lb_prefill  (m_lb_prefill),
    .rx_mon         (rx_mon),
    .tx_mon         (tx_mon)
);
assign mac_status = {4'h0, tx_heartbeat[26], rx_heartbeat[26], tx_mon, rx_mon};
endmodule
