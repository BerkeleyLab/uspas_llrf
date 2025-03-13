`define LB_DECODE_marble_bsp
`include "settings.vams"
`include "marble_bsp_auto.vh"
module marble_bsp #(
    parameter IP ={8'd192, 8'd168, 8'd19, 8'd122},
    parameter MAC = 48'h00105ad155b2,

    parameter LB_READ_DELAY = 3,
    parameter DEFAULT_ENABLE_RX = 1,
    parameter integer EVR_COMMAS_NEEDED = 60,
    parameter integer EVR_CHECK_TIMEOUT = 125000,  // 125e6 Hz * 1ms
    parameter FCNT_WIDTH = 16  // freq_count update rate: 125M / 2**16 = 1.9kHz.
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
    output          BOOT_CCLK,
    input           BOOT_MISO,
    output          BOOT_MOSI,

    // Clocks
    input           clk_locked,
    input           clk_200,
    input           dsp_clk,
    input           gtx_refclk,
    output          gtx_rxclk,

    // lb controller
    output          m_lb_clk,
    output [23:0]   m_lb_addr,
    output          m_lb_write,
    output          m_lb_read,
    output [31:0]   m_lb_wdata,
    input  [31:0]   m_lb_rdata,
    output          m_lb_rvalid,
    output          m_lb_prefill,

    // lb peripheral, 0 - 0x3ffff
    input           lb_clk,
    input [17:0]    lb_addr,
    input           lb_write,
    input           lb_read,
    input           lb_rvalid,
    input [31:0]    lb_wdata,
    output [31:0]   lb_rdata,

    // GTX related
    input           evr_gtx_rxn,
    input           evr_gtx_rxp,
    output [15:0]   gtx_rxdata,
    output [1:0]    gtx_rxcharisk,

    // diagnostics
    output          in_use,
    output [7:0]    mac_status,

    // external trigger related
    inout  [3:0]   zest_pmod,  // top row of pins J18 on Zest next to ground pin
    // top row of pins J12 on Marble used for data
    // bottom row used to set direction
    // feature of BNC board
    inout  [3:0]   pmod_J12,
    output reg [3:0]   pmod_J12_dir,
    output [15:0]  etrig_pulse_cnt,
    output         etrig_pulse,
    output         etrig_pulse_delay
);

wire [31:0] lb_data = lb_wdata; // for newad.py
// GTX reset registers are all async
// newad-force lb domain
// reg [0:0] gtx_soft_reset; top-level
// reg [0:0] gtx_rx_slide_req; top-level
// reg [1:0] etrig_pmod_sel; top-level

`AUTOMATIC_decode

// in lb_clk domain
wire gtx_rx_fsm_resetdone, gtx_rx_aligned;
wire [31:0] gtx_rx_reset_cnt;

wire [27:0] gtx_rx_clk_frequency;
wire [27:0] gtx_refclk_frequency;
// ----------------------------------
// GTX instance
// ---------------------------------
evr_gtx_wrapper #(
    .COMMAS_NEEDED  (EVR_COMMAS_NEEDED),
    .CHECK_TIMEOUT  (EVR_CHECK_TIMEOUT)
) evr_gtx_wrapper_i(
    .sys_clk            (lb_clk),
    .gtx_refclk         (gtx_refclk),
    .evr_gtx_rxn        (evr_gtx_rxn),
    .evr_gtx_rxp        (evr_gtx_rxp),

    .soft_reset         (gtx_soft_reset),
    .rx_fsm_reset_done  (gtx_rx_fsm_resetdone),
    .rx_aligned_sys     (gtx_rx_aligned),
    .rx_reset_cnt       (gtx_rx_reset_cnt),
    .rx_slide_req       (gtx_rx_slide_req),

    .rx_usrclk          (gtx_rxclk),
    .rxdata             (gtx_rxdata),
    .rxcharisk          (gtx_rxcharisk)
);

// Total miscellaneous
// See below for mac_status assignment
reg [7:0] mac_status_r=0;  always @(posedge lb_clk) mac_status_r <= mac_status;

// ---------------------
// Measure and report GTX RX recovered clock
// ---------------------
freq_count #(.refcnt_width (FCNT_WIDTH)) fcnt_gtx_rx_clk (
    .sysclk     (lb_clk),
    .f_in       (gtx_rxclk),
    .frequency  (gtx_rx_clk_frequency)
);
freq_count #(.refcnt_width (FCNT_WIDTH)) fcnt_gtx_refclk (
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
wire [13:0] ph_diff_adv_ = PH_DIFF_ADV;
wire signed [PH_DIFF_DW-1:0] evr_dsp_phsdiff;
phase_diff #(
    .dw             (PH_DIFF_DW+1)
) phase_diff_evr (
    .uclk1          (gtx_rxclk),
    .uclk2          (dsp_clk),
    .uclk2g         (1'b1),
    .adv            (ph_diff_adv_),
    .sclk           (clk_200),
    .rclk           (lb_clk),
    .phdiff_out     (evr_dsp_phsdiff)
);

wire enable_rx;
wire config_s, config_p;
wire [7:0] config_a, config_d;
wire [7:0] mbox_out;
wire addrhit_mbox = lb_addr[17:12] == 6'h01; // 0x01000-0x01fff
wire lb_mbox_write = lb_write & addrhit_mbox;

mmc_mailbox #(
    .DEFAULT_ENABLE_RX(DEFAULT_ENABLE_RX)
) mailbox_i (
    .clk                (lb_clk),  // input
    // localbus mailbox memory interface
    .lb_addr            (lb_addr[10:0]), // input [10:0]
    .lb_din             (lb_wdata[7:0]), // input [7:0]
    .lb_dout            (mbox_out),      // output [7:0]
    .lb_write           (lb_mbox_write), // input
    .lb_control_strobe  (lb_read),       // input
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

// matches LCLS-II
wire de9_dsr, de9_rxd;
assign de9_rxd = zest_pmod[0];
assign de9_dsr = zest_pmod[1];
// capture these in dsp_clk domain before doing etrig logic with them
reg de9_rxd_r=0, de9_dsr_r=0;
always @(posedge dsp_clk) begin
  de9_rxd_r <= de9_rxd;
  de9_dsr_r <= de9_dsr;
end

reg [1:0] etrig_pmod_sel_x=0, etrig_pmod_sel_r=0;
always @(posedge dsp_clk) begin
  etrig_pmod_sel_x <= etrig_pmod_sel;
  etrig_pmod_sel_r <= etrig_pmod_sel_x;
end
// Calculate the direction control pin index
// check: https://gitlab.lbl.gov/hardware-designs/bnc4x_v1/-/blob/main/README.md?ref_type=heads
wire [3:0] sel_mask = 4'b1 << etrig_pmod_sel_r;
reg [1:0] etrig_sel_r=0;
always @(posedge dsp_clk) begin
  // Note that etrig_sel is constructed by newad based on the sel port of instance etrig.
  // Its existence and properties are not explicitly mentioned in this module.
  etrig_sel_r <= etrig_sel;  // coerce clock domain
  pmod_J12_dir <= ~((etrig_sel_r == 1) ? sel_mask : 4'b0);
end
// create the IOB for input signals from Pmod
reg [3:0] pmod_J12_capture=0;
always @(posedge dsp_clk) pmod_J12_capture <= pmod_J12;
// and choose one of those bits to send to etrig_bridge
wire pmod_trig = pmod_J12_capture[etrig_pmod_sel_r];

// external trigger selection
etrig_bridge etrig // auto
(
  .lb_clk(lb_clk),
  .adc_clk(dsp_clk),
  // Three possible external triggers
  // unused
  .trign_0(1'b0),
  // Connected to one of the PMODs
  .trign_1(pmod_trig),
  // DB9 connector used for AWA
  .trign_2(de9_rxd_r & de9_dsr_r),
  // Trigger Counter
  .etrig_pulse_cnt(etrig_pulse_cnt),
  // Trigger Outputs
  .etrig_pulse(etrig_pulse),
  .etrig_pulse_delayed(etrig_pulse_delay),
  //Control registers
  `AUTOMATIC_etrig
);

// ---------------------
// read / write buffer, reserved for housekeeping info
// ---------------------
wire [7:0] lb_rdata_buf;
wire lb_buf_wen = lb_write & (lb_addr[17:12]==3);     // 0x3000 - 0x3fff, 4k bytes
dpram #(
    .dw(8),
    .aw(12)
) dpram_buf (
    .clka   (lb_clk),
    .addra  (lb_addr[11:0]),
    .dina   (lb_wdata[7:0]),
    .wena   (lb_buf_wen),
    .clkb   (lb_clk),
    .addrb  (lb_addr[11:0]),
    .doutb  (lb_rdata_buf)
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
        4'h4: reg_bank_0 <= gtx_rx_fsm_resetdone;
        4'h5: reg_bank_0 <= gtx_rx_aligned;
        4'h6: reg_bank_0 <= evr_dsp_phsdiff;
        4'h7: reg_bank_0 <= gtx_rx_reset_cnt;
        default: reg_bank_0 <= 32'hdeadface;
    endcase
end

always @(posedge lb_clk) if (lb_read) begin
    lb_addr_d1 <= lb_addr;
    casez (lb_addr_d1)
        18'h00???: lb_rdata_r <= mirror_out_0;  // automatic address map
        // 18'h001??? reserved for mailbox. See 'addrhit_mbox' below.
        18'h0200?: lb_rdata_r <= reg_bank_0;
        18'h03???: lb_rdata_r <= lb_rdata_buf;
        default:   lb_rdata_r <= 32'hfaceface;
    endcase
end

// The mailbox readout from fake_dpram can't be registered again
assign lb_rdata = addrhit_mbox ? {24'h000000, mbox_out} : lb_rdata_r;

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
