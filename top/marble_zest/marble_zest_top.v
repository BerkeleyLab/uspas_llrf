module marble_zest_top #(
    parameter IP ={8'd192, 8'd168, 8'd19, 8'd122},
    parameter MAC = 48'h00105ad155b2,
    parameter LB_READ_DELAY=3,
    parameter LB_ADW = 18,
    parameter DEFAULT_ENABLE_RX = 1
) (
    // Marble
    input           GTPREFCLK_P,
    input           GTPREFCLK_N,

    output [3:0]    RGMII_TXD,
    output          RGMII_TX_CTRL,
    output          RGMII_TX_CLK,
    input [3:0]     RGMII_RXD,
    input           RGMII_RX_CTRL,
    input           RGMII_RX_CLK,

    output          PHY_RSTN,

    output [7:0]    PMOD1,
    output [7:0]    PMOD2,

    inout           I2C_SCL,
    inout           I2C_SDA,
    output          I2C_RST,

    input           UART_CTS,
    output          UART_TX,
    input           UART_RX,

    // Mailbox SPI
    input           FPGA_SCK,
    input           FPGA_CSB,
    input           FPGA_PICO,
    output          FPGA_POCI,

    // Zest
    output          ZEST_ADC_PDWN,
    output          ZEST_ADC_CSB_0,
    output          ZEST_ADC_SYNC,
    output          ZEST_SCLK,       // ADC0, ADC1, DAC
    output          ZEST_SDI,        // LMK, DAC_SDIO
    output          ZEST_ADC_CSB_1,
    output          ZEST_LMK_LEUWIRE,
    output          ZEST_PWR_SYNC,
    output          ZEST_PWR_EN,
    output          ZEST_AD7794_FCLK,
    output          ZEST_DAC_CSB,
    output          ZEST_AMC7823_SPI_SS,
    output          ZEST_AD7794_CSB,
    output          ZEST_DAC_RESET,
    output          ZEST_POLL_SCLK,  // AMC7823, AD7794
    output          ZEST_POLL_MOSI,  // AMC7823, AD7794
    output          ZEST_ADC_SDIO_DIR,
    inout           ZEST_ADC_SDIO,   // ADC0, ADC1
    input           ZEST_AMC7823_SPI_MISO,
    input           ZEST_LMK_DATAUWIRE,
    input           ZEST_AD7794_DOUT,
    input           ZEST_DAC_SDO,

    input [1:0]     ZEST_CLK_TO_FPGA_P,
    input [1:0]     ZEST_CLK_TO_FPGA_N,

    input [7:0]     ZEST_ADC_D0_P,
    input [7:0]     ZEST_ADC_D0_N,
    input [7:0]     ZEST_ADC_D1_P,
    input [7:0]     ZEST_ADC_D1_N,
    input [1:0]     ZEST_ADC_DCO_P,
    input [1:0]     ZEST_ADC_DCO_N,
    input [1:0]     ZEST_ADC_FCO_P,
    input [1:0]     ZEST_ADC_FCO_N,

    output [13:0]   ZEST_DAC_D_P,
    output [13:0]   ZEST_DAC_D_N,
    output          ZEST_DAC_DCI_P,
    output          ZEST_DAC_DCI_N,
    input           ZEST_DAC_DCO_P,
    input           ZEST_DAC_DCO_N,

    inout [7:0]     ZEST_PMOD1,
    inout [7:0]     ZEST_PMOD2,
    inout           ZEST_HDMI_CK_P,
    inout           ZEST_HDMI_CK_N,
    inout           ZEST_HDMI_D0_P,
    inout           ZEST_HDMI_D0_N,
    inout           ZEST_HDMI_D1_P,
    inout           ZEST_HDMI_D1_N,
    inout           ZEST_HDMI_D2_P,
    inout           ZEST_HDMI_D2_N,
    inout           ZEST_HDMI_DET,
    inout           ZEST_HDMI_SCL,
    inout           ZEST_HDMI_SDA,
    inout           ZEST_HDMI_CEC,
    inout           ZEST_APP_I2C_SDA,
    inout           ZEST_APP_I2C_SCL
);

// ----------------------------------
// Clocking and reset
// ---------------------------------

// Combine the 2 reset sources (USB, button)
wire clk;
wire clk_200;
wire gmii_tx_clk90;
wire clk_locked;

wire gtpclk0, gtpclk;
IBUFDS_GTE2 passi_125(
    .I(GTPREFCLK_P), .IB(GTPREFCLK_N), .CEB(1'b0), .O(gtpclk0)
);
// UG472 Figure 1-4
BUFH passg_125(
    .I(gtpclk0), .O(gtpclk)
);

// XXX move to system.v
wire gmii_tx_clk, gmii_rx_clk;
xilinx7_clocks #(
    .DIFF_CLKIN("BYPASS"),
    .CLKIN_PERIOD(8),  // REFCLK = 125 MHz
    .MULT     (8),     // 125 MHz X 8 = 1 GHz on-chip VCO
    .DIV0     (8),     // 1 GHz / 8 = 125 MHz
    .DIV1     (5)      // 1 GHz / 5 = 200 MHz
) clocks_i(
    .sysclk_p (gtpclk),
    .sysclk_n (1'b0),
    .reset    (1'b0),
    .clk_out0 (gmii_tx_clk),
    .clk_out1 (clk_200),
    .clk_out2 (gmii_tx_clk90),
    .locked   (clk_locked)
);

// ----------------------------------
// MMC mailbox instance
// ---------------------------------

wire enable_rx;
wire config_s, config_p;
wire [7:0] config_a, config_d;

mmc_mailbox #(
    .DEFAULT_ENABLE_RX(DEFAULT_ENABLE_RX)
) mailbox_i (
    .clk(gmii_tx_clk), // input
    // localbus mailbox memory interface
    .lb_addr(11'h000), // input [10:0]
    .lb_din(8'h00), // input [7:0]
    .lb_dout(), // output [7:0]
    .lb_write(1'b0), // input
    .lb_control_strobe(1'b0), // input
    // SPI PHY
    .sck(FPGA_SCK), // input
    .ncs(FPGA_CSB), // input
    .pico(FPGA_PICO), // input
    .poci(FPGA_POCI), // output
    // Config pins for badger (rtefi) interface
    .config_s(config_s), // output
    .config_p(config_p), // output
    .config_a(config_a), // output [7:0]
    .config_d(config_d), // output [7:0]
    // Special pins
    .enable_rx(enable_rx), // output
    .spi_pins_debug() // {MISO, din, sclk_d1, csb_d1};
);

// ----------------------------------
// Ethernet/UDP bridge
// ---------------------------------

// localbus master
wire lb0_write;
wire lb0_read;
wire lb0_rvalid;
wire [23:0] lb0_addr;
wire [31:0] lb0_wdata;
wire [31:0] lb0_rdata;
wire [7:0]  mac_status;
udp_rgmii #(
    .IP(IP), .MAC(MAC), .LB_READ_DELAY(LB_READ_DELAY)
) udp_rgmii_i (
    .RGMII_TXD      (RGMII_TXD    ),
    .RGMII_TX_CTRL  (RGMII_TX_CTRL),
    .RGMII_TX_CLK   (RGMII_TX_CLK ),
    .RGMII_RXD      (RGMII_RXD    ),
    .RGMII_RX_CTRL  (RGMII_RX_CTRL),
    .RGMII_RX_CLK   (RGMII_RX_CLK ),
    .PHY_RSTN       (PHY_RSTN     ),
    .clk_locked     (clk_locked   ),
    .gmii_tx_clk    (gmii_tx_clk  ),
    .gmii_tx_clk90  (gmii_tx_clk90),
    .gmii_rx_clk    (gmii_rx_clk  ),

    .host_clk       (gmii_tx_clk  ),
    .host_waddr     (11'h0        ),
    .host_write     (1'b0         ),
    .host_wdata     (16'h0        ),
    .tx_mac_done    (             ),

    .lb_clk         (clk          ),
    .lb_addr        (lb0_addr     ),
    .lb_write       (lb0_write    ),
    .lb_read        (lb0_read     ),
    .lb_wdata       (lb0_wdata    ),
    .lb_rdata       (lb0_rdata    ),
    .lb_rvalid      (lb0_rvalid   ),
    .mac_status     (mac_status   ),

    .enable_rx      (enable_rx    ),
    .config_a       (config_a[3:0]),
    .config_d       (config_d     ),
    .config_s       (config_s     ),
    .config_p       (config_p     )
);

// merged localbus master
wire lb_write;
wire lb_read;
wire lb_rvalid;
wire [LB_ADW-1:0] lb_addr;
wire [31:0] lb_wdata;
wire [31:0] lb_rdata;

wire [31:0] gpio_z;
wire rst;
wire [68:0]       mem_packed_fwd;
wire [32:0]       mem_packed_ret;
wire trap;
reg reset_r=0;
always @(posedge clk) reset_r <= UART_CTS;
wire reset_system = (UART_CTS & ~reset_r);

// ----------------------------------
// PicoRV Subsystem
// ---------------------------------

system #(
    .LB_READ_DELAY(LB_READ_DELAY),
    .SYSTEM_HEX_PATH("system32.dat")
) system_inst (
    .clk            (clk),
    .cpu_reset      (reset_system),
    .gpio_z         (gpio_z),
    .uart_tx        (UART_TX),
    .uart_rx        (UART_RX),
    .trap           (trap ),
    .lb_write       (lb0_write),
    .lb_read        (lb0_read),
    .lb_addr        (lb0_addr[LB_ADW-1:0]),
    .lb_wdata       (lb0_wdata),
    .lb_rdata       (lb0_rdata),
    .lb_rvalid      (lb0_rvalid),
    .lb_merge_write (lb_write),
    .lb_merge_read  (lb_read),
    .lb_merge_addr  (lb_addr),
    .lb_merge_wdata (lb_wdata),
    .lb_merge_rdata (lb_rdata),
    .lb_merge_rvalid(lb_rvalid),
    .rst            (rst),
    .mem_packed_fwd (mem_packed_fwd),
    .mem_packed_ret (mem_packed_ret)
);

// ----------------------------------
// LLRF Subsystem
// ---------------------------------

wire        dsp_clk;
wire [1:0]  clk_div_out;
wire [16*8-1:0] adc_out_data;
wire [7:0]  adc_out_clk;
wire [15:0] dac_a_out;
wire [15:0] dac_b_out;

`ifndef GIT_32BIT_ID
`define GIT_32BIT_ID 32'hdeadf00d
`endif

llrf_shell #(.GIT_REV_ID(`GIT_32BIT_ID)) llrf_inst (
    .lb_clk         (clk),
    .lb_write       (lb_write),
    .lb_addr        (lb_addr),
    .lb_wdata       (lb_wdata),
    .lb_rdata       (lb_rdata),
    .lb_read        (lb_read),
    .lb_rvalid      (lb_rvalid),

    .dsp_clk        (dsp_clk),
    .adc_data_in    (adc_out_data),
    .dac_data_a_out (dac_a_out),
    .dac_data_b_out (dac_b_out),

    .drive_permit_in (1'b1),
    .slow_permit_in (1'b1)
);

// ----------------------------------
// Zest Digitizer Board
// ---------------------------------

zest #(
    .PH_DIFF_ADV (`PH_DIFF_ADV),
    .CLKIN_PERIOD(`CLKIN_PERIOD),
    .BASE_ADDR  (8'h05),
    .FCNT_WIDTH (16)
) zest_inst (
    .ADC_PDWN       (ZEST_ADC_PDWN      ),
    .ADC_CSB_0      (ZEST_ADC_CSB_0     ),
    .ADC_SYNC       (ZEST_ADC_SYNC      ),
    .SCLK           (ZEST_SCLK          ),
    .SDI            (ZEST_SDI           ),
    .ADC_CSB_1      (ZEST_ADC_CSB_1     ),

    .LMK_LEUWIRE    (ZEST_LMK_LEUWIRE   ),
    .PWR_SYNC       (ZEST_PWR_SYNC      ),
    .PWR_EN         (ZEST_PWR_EN        ),
    .AD7794_FCLK    (ZEST_AD7794_FCLK   ),

    .DAC_CSB        (ZEST_DAC_CSB       ),
    .AMC7823_SPI_SS (ZEST_AMC7823_SPI_SS),
    .AD7794_CSB     (ZEST_AD7794_CSB    ),
    .DAC_RESET      (ZEST_DAC_RESET     ),
    .POLL_SCLK      (ZEST_POLL_SCLK     ),
    .POLL_MOSI      (ZEST_POLL_MOSI     ),

    .ADC_SDIO_DIR   (ZEST_ADC_SDIO_DIR  ),
    .ADC_SDIO       (ZEST_ADC_SDIO      ),

    .AMC7823_SPI_MISO (ZEST_AMC7823_SPI_MISO),
    .LMK_DATAUWIRE  (ZEST_LMK_DATAUWIRE ),
    .AD7794_DOUT    (ZEST_AD7794_DOUT   ),
    .DAC_SDO        (ZEST_DAC_SDO       ),

    .CLK_TO_FPGA_P  (ZEST_CLK_TO_FPGA_P[1] ),   // FMC2_CLK0_M2C_P
    .CLK_TO_FPGA_N  (ZEST_CLK_TO_FPGA_N[1] ),   // FMC2_CLK0_M2C_N

    .ADC_D0_P       (ZEST_ADC_D0_P      ),
    .ADC_D0_N       (ZEST_ADC_D0_N      ),
    .ADC_D1_P       (ZEST_ADC_D1_P      ),
    .ADC_D1_N       (ZEST_ADC_D1_N      ),
    .ADC_DCO_P      (ZEST_ADC_DCO_P     ),
    .ADC_DCO_N      (ZEST_ADC_DCO_N     ),
    .ADC_FCO_P      (ZEST_ADC_FCO_P     ),
    .ADC_FCO_N      (ZEST_ADC_FCO_N     ),

    .DAC_D_P        (ZEST_DAC_D_P       ),
    .DAC_D_N        (ZEST_DAC_D_N       ),
    .DAC_DCI_P      (ZEST_DAC_DCI_P     ),
    .DAC_DCI_N      (ZEST_DAC_DCI_N     ),
    .DAC_DCO_P      (ZEST_DAC_DCO_P     ),
    .DAC_DCO_N      (ZEST_DAC_DCO_N     ),

    .dsp_clk_out    (dsp_clk),
    .clk_div_out    (clk_div_out),
    .adc_out_clk    (adc_out_clk),
    .adc_out_data   (adc_out_data),
    .dac_in_data_i  (dac_a_out[15:2]),
    .dac_in_data_q  (dac_b_out[15:2]),

    .clk_200        (clk_200       ),
    .clk            (clk           ),
    .rst            (rst           ),
    .mem_packed_fwd (mem_packed_fwd),
    .mem_packed_ret (mem_packed_ret)
);

IDELAYCTRL idelayctrl_inst (
  .RST          ( reset_system ),
  .REFCLK       ( clk_200      ),
  .RDY          (              )
);

/// #define PIN_I2C_SDA              0
/// #define PIN_I2C_SCL              1
/// #define PIN_PCA9548_RST          2
assign I2C_SDA      = gpio_z[0];
assign I2C_SCL      = gpio_z[1];
assign I2C_RST      = gpio_z[2]; // to enable I2C mux, set high

assign PMOD1 = {mac_status};
assign PMOD2 = {trap, gpio_z[30:24]};

endmodule
