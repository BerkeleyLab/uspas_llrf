`define LB_DECODE_marble_bsp
`include "settings.vams"
`include "marble_bsp_auto.vh"
module marble_bsp #(
    parameter IP ={8'd192, 8'd168, 8'd19, 8'd122},
    parameter MAC = 48'h00105ad155b2,
    parameter LB_READ_DELAY = 3,
    parameter DEFAULT_ENABLE_RX = 1,
    parameter refcnt_w = 24
) (
    // GMII (ready for simulation with infrastructure demoed in badger/tests)
    input           gmii_tx_clk,
    output [7:0]    gmii_txd,
    output          gmii_tx_en,
    output          gmii_tx_er,
    input           gmii_rx_clk,
    input [7:0]     gmii_rxd,
    input           gmii_rx_dv,
    input           gmii_rx_er,
    output          PHY_RSTN,

    // Mailbox SPI
    input           FPGA_SCK,
    input           FPGA_CSB,
    input           FPGA_PICO,
    output          FPGA_POCI,

    // SPI boot flash programming port
    output          BOOT_CS_B,
    input           BOOT_MISO,
    output          BOOT_MOSI,

    // Clocks
    input           clk_locked,
    input           clk_200,
    input           dsp_clk,
    input           gtx_refclk,
    output          gtx_rx_bufg_outclk,

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

    // GTX related
    input           QSFP2_RXN,
    input           QSFP2_RXP,
    output [15:0]   gtx_rxdata_good,
    output [1:0]    gtx_rxcharisk_good,

    // diagnostics
    output          in_use,
    output [7:0]    mac_status
);

wire [31:0] lb_data = lb_wdata; // for newad.py
// GTX reset registers are all async
// newad-force lb domain
// reg [0:0] gt_rxreset; top-level
// reg [0:0] gtx_cpll_reset; top-level
// reg [0:0] gtx_soft_reset; top-level
// reg [0:0] gtx_rx_pmareset; top-level
// reg [0:0] gtx_rx_slide_req; top-level

`AUTOMATIC_decode

// this status register is async
reg [0:0] gtx_cpll_locked=0;

// in gtx_rx_bufg_outclk domain
reg [0:0] gtx_rx_resetdone=0;
reg [0:0] gtx_rx_aligned=0;
reg [1:0] gtx_rx_notintable=0;

wire [27:0] gtx_rx_clk_frequency;
wire [27:0] gtx_refclk_frequency;
wire [31:0] us_since_boot;
// ----------------------------------
// GTX instance
// ---------------------------------
wire rx_resetdone, cpll_locked, rx_aligned;
wire [1:0] rx_notintable;
gtx_wrapper #(
    .QSFP_WI(16),
    .DEBUG("false")
) gtx_wrapper_i(
    .sys_clk        (m_lb_clk),
    .gtx_refclk     (gtx_refclk),
    .QSFP2_RXN      (QSFP2_RXN),
    .QSFP2_RXP      (QSFP2_RXP),
    .gt_rxreset     (gt_rxreset),
    .cpll_reset     (gtx_cpll_reset),
    .soft_reset     (gtx_soft_reset),
    .rx_pmareset    (gtx_rx_pmareset),
    .rx_slide_req   (gtx_rx_slide_req),

    .rx_bufg_outclk (gtx_rx_bufg_outclk),
    .rxdata_good    (gtx_rxdata_good),
    .rxcharisk_good (gtx_rxcharisk_good),

    .rx_resetdone   (rx_resetdone),
    .rx_aligned     (rx_aligned),
    .rx_notintable  (rx_notintable),
    .cpll_locked    (cpll_locked),
    .us_since_boot  (us_since_boot)
);

// CDC GTX related
always @(posedge lb_clk) gtx_rx_resetdone <= rx_resetdone;
always @(posedge lb_clk) gtx_rx_aligned <= rx_aligned;
always @(posedge lb_clk) gtx_cpll_locked <= cpll_locked;
always @(posedge lb_clk) gtx_rx_notintable <= rx_notintable;

// Total miscellaneous
// See below for mac_status assignment
reg [7:0] mac_status_r=0;  always @(posedge lb_clk) mac_status_r <= mac_status;

// ---------------------
// Measure and report GTX RX recovered clock
// ---------------------
freq_count #(.refcnt_width (refcnt_w), .freq_width (28)) fcnt_gtx_rx_clk (
    .sysclk     (lb_clk),
    .f_in       (gtx_rx_bufg_outclk),
    .frequency  (gtx_rx_clk_frequency)
);
freq_count #(.refcnt_width (refcnt_w), .freq_width (28)) fcnt_gtx_refclk (
    .sysclk     (lb_clk),
    .f_in       (gtx_refclk),
    .frequency  (gtx_refclk_frequency)
);

// Measure the phase difference between dsp_clk and evr_clk.
// Do nothing about it yet, just let people read it through localbus.
// In the LEMP system, theory says this will be quasi-static,
// just representing divider state and cable drift.
localparam PH_DIFF_DW = 13;
localparam integer  PH_DIFF_ADV = $rtoi((1/`DSP_CLK_CYCLE) / 0.200 * (2**PH_DIFF_DW));
wire signed [PH_DIFF_DW-1:0] evr_dsp_phsdiff;
phase_diff #(
    .adv            (PH_DIFF_ADV),
    .dw             (PH_DIFF_DW+1)
) phase_diff_evr (
    .uclk1          (gtx_rx_bufg_outclk),
    .ext_div1       (1'b0),
    .uclk2          (dsp_clk),
    .ext_div2       (1'b0),
    .sclk           (clk_200),
    .rclk           (lb_clk),
    .dval           (),
    .phdiff_out     (evr_dsp_phsdiff)
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

// ---------------------
// Read-only address space decoding
// ---------------------
localparam integer LB_ADW = 18;
reg [31:0] lb_rdata_r=0;
reg [LB_ADW-1:0] lb_addr_d1=0;
reg [31:0] reg_bank_0=0;

// reverse_json_offset: 270336
always @(posedge lb_clk) if(lb_read) begin
    case (lb_addr[3:0])
        4'h1: reg_bank_0 <= mac_status_r;  // alias mac_status
        4'h2: reg_bank_0 <= gtx_rx_clk_frequency;
        4'h3: reg_bank_0 <= gtx_refclk_frequency;
        4'h4: reg_bank_0 <= gtx_rx_resetdone;
        4'h5: reg_bank_0 <= gtx_rx_aligned;
        4'h6: reg_bank_0 <= gtx_cpll_locked;
        4'h7: reg_bank_0 <= gtx_rx_notintable;
        4'h8: reg_bank_0 <= us_since_boot;
        4'h9: reg_bank_0 <= evr_dsp_phsdiff;
        default: reg_bank_0 <= 32'hdeadface;
    endcase
end

// lb_read: Match READ_DELAY=3 in system.v, check timing in simulation
always @(posedge lb_clk) if (lb_read) begin
    lb_addr_d1 <= lb_addr;
    casez (lb_addr_d1)
        18'h00???: lb_rdata_r <= mirror_out_0;  // automatic address map
        18'h01???: lb_rdata_r <= mbox_out;
        18'h0200?: lb_rdata_r <= reg_bank_0;
        default:   lb_rdata_r <= 32'hfaceface;
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

wire BOOT_CCLK;
`ifndef SIMULATE
`ifndef YOSYS
STARTUPE2 set_cclk(.USRCCLKO(BOOT_CCLK), .USRCCLKTS(1'b0));
`endif
`endif

// localbus master
wire rx_mon;
wire tx_mon;
wire blob_in_use, boot_busy;
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
    .tx_mon         (tx_mon),

    .p4_spi_clk     (BOOT_CCLK),
    .p4_spi_cs      (BOOT_CS_B),
    .p4_spi_mosi    (BOOT_MOSI),
    .p4_spi_miso    (BOOT_MISO),
    .p4_busy        (boot_busy),
    .in_use         (blob_in_use)
);

assign in_use = blob_in_use | boot_busy;

// Not in a single clock domain, but keep it that way for
// all-else-fails level debugging, e.g., sending to LEDs on a Pmod.
// See above for code that captures it for localbus monitoring.
assign mac_status = {4'h0, tx_heartbeat[26], rx_heartbeat[26], tx_mon, rx_mon};

endmodule
