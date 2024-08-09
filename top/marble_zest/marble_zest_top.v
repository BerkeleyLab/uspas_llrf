module marble_zest_top #(
    parameter IP ={8'd192, 8'd168, 8'd19, 8'd122},
    parameter MAC = 48'h00105ad155b2,
    parameter LB_READ_DELAY=3
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

// ---------------------------------
// Clocking and reset
// ---------------------------------

// Combine the 2 reset sources (USB, button)
wire clk;
wire clk_200;
wire gmii_tx_clk90;
wire idelayctrl_ready;
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

wire idelay_reset = ~clk_locked;
IDELAYCTRL idelayctrl_inst (
  .RST        (idelay_reset ),
  .REFCLK     (clk_200      ),
  .RDY        (idelayctrl_ready)
);

// ---------------------------------
// Ethernet/UDP bridge
// ---------------------------------

// localbus master declaration, driven by badger
wire        m_lb_clk;
wire        m_lb_write;
wire        m_lb_read;
wire        m_lb_rvalid;
wire [23:0] m_lb_addr;
wire [31:0] m_lb_wdata;
wire [31:0] m_lb_rdata;
wire        m_lb_prefill;
wire [7:0]  mac_status;

assign clk = m_lb_clk;
wire lb_prefill = m_lb_prefill;

// localbus declaration
wire lb_clk = clk;
wire lb_write;
wire lb_read;
wire lb_rvalid;
wire [21:0] lb_addr;
wire [31:0] lb_wdata;
wire [31:0] lb_rdata;

wire [31:0] gpio_z;
wire rst;
wire [68:0] mem_packed_fwd;
wire [32:0] mem_packed_ret;
wire trap;

reg uart_cts1=0;
always @(posedge clk) uart_cts1 <= UART_CTS;
wire uart_cts_r = UART_CTS & ~uart_cts1;
// keep system in reset before idelayctrl is ready
wire reset_system = uart_cts_r | ~idelayctrl_ready;

// ----------------------------------
// PicoRV Subsystem
// ---------------------------------
// 22 bit local bus address width
// 4 bit msb multiplexing
// 18 bit peripheral address width
system #(
    .LB_READ_DELAY(LB_READ_DELAY),
    .LB_ADW(22),
    .SYSTEM_HEX_PATH("system32.dat")
) system_inst (
    .clk            (clk),
    .cpu_reset      (reset_system),
    .gpio_z         (gpio_z),
    .uart_tx        (UART_TX),
    .uart_rx        (UART_RX),
    .trap           (trap ),
    .lb_write       (m_lb_write),
    .lb_read        (m_lb_read),
    .lb_addr        (m_lb_addr[21:0]),
    .lb_wdata       (m_lb_wdata),
    .lb_rdata       (m_lb_rdata),
    .lb_rvalid      (m_lb_rvalid),
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

// Localbus multiplixer
//     0 to 3ffff: lb_base_0
// 40000 to 7ffff: lb_base_1
// 80000 to bffff: lb_base_2
// c0000 to fffff: lb_base_3
// ...
wire [3:0] lb_addr_mux = lb_addr[18+:4];
wire lb_base_0 = (lb_addr_mux == 4'h0);
wire lb_base_1 = (lb_addr_mux == 4'h1);
wire lb_base_2 = (lb_addr_mux == 4'h2);
wire lb_base_3 = (lb_addr_mux == 4'h3);
wire lb_write_0 = lb_write & lb_base_0;
wire lb_write_1 = lb_write & lb_base_1;
wire lb_write_2 = lb_write & lb_base_2;
wire lb_write_3 = lb_write & lb_base_3;
wire lb_read_0  = lb_read & lb_base_0;
wire lb_read_1  = lb_read & lb_base_1;
wire lb_read_2  = lb_read & lb_base_2;
wire lb_read_3  = lb_read & lb_base_3;
wire [31:0] lb_rdata_0, lb_rdata_1, lb_rdata_2, lb_rdata_3;
reg [31:0] lb_rdata_r=0;

// XXX move config_romx here from llrf_shell.v
always @(*) begin
    case(lb_addr_mux)
    4'h0: lb_rdata_r = lb_rdata_0;
    4'h1: lb_rdata_r = lb_rdata_1;
    default: lb_rdata_r = 32'hdeaddead;
    endcase
end
assign lb_rdata = lb_rdata_r;

// ----------------------------------
// LLRF Subsystem, @ lb_base_0
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
    .lb_clk         (lb_clk),
    .lb_addr        (lb_addr[17:0]),
    .lb_write       (lb_write_0),
    .lb_read        (lb_read_0),
    .lb_wdata       (lb_wdata),
    .lb_rdata       (lb_rdata_0),
    .lb_rvalid      (lb_rvalid),
    .lb_prefill     (lb_prefill),

    .dsp_clk        (dsp_clk),
    .adc_data_in    (adc_out_data),
    .dac_data_a_out (dac_a_out),
    .dac_data_b_out (dac_b_out),

    .drive_permit_in (1'b1),
    .slow_permit_in  (1'b1)
);

// ----------------------------------
// Marble Board Support (MMC, Badger, GTX, etc.), @ lb_base_1
// ---------------------------------
udp_rgmii #(
    .IP(IP), .MAC(MAC), .LB_READ_DELAY(LB_READ_DELAY)
) marble_inst (
    .RGMII_TXD      (RGMII_TXD    ),
    .RGMII_TX_CTRL  (RGMII_TX_CTRL),
    .RGMII_TX_CLK   (RGMII_TX_CLK ),
    .RGMII_RXD      (RGMII_RXD    ),
    .RGMII_RX_CTRL  (RGMII_RX_CTRL),
    .RGMII_RX_CLK   (RGMII_RX_CLK ),
    .PHY_RSTN       (PHY_RSTN     ),

    .FPGA_SCK       (FPGA_SCK     ),
    .FPGA_CSB       (FPGA_CSB     ),
    .FPGA_PICO      (FPGA_PICO    ),
    .FPGA_POCI      (FPGA_POCI    ),

    .clk_locked     (clk_locked   ),
    .gmii_tx_clk    (gmii_tx_clk  ),
    .gmii_tx_clk90  (gmii_tx_clk90),
    .gmii_rx_clk    (gmii_rx_clk  ),

    .m_lb_clk       (m_lb_clk     ),
    .m_lb_addr      (m_lb_addr     ),
    .m_lb_write     (m_lb_write    ),
    .m_lb_read      (m_lb_read     ),
    .m_lb_wdata     (m_lb_wdata    ),
    .m_lb_rdata     (m_lb_rdata    ),
    .m_lb_rvalid    (m_lb_rvalid   ),
    .m_lb_prefill   (m_lb_prefill  ),

    .lb_clk         (lb_clk        ),
    .lb_addr        (lb_addr[17:0] ),
    .lb_write       (lb_write_1    ),
    .lb_read        (lb_read_1     ),
    .lb_wdata       (lb_wdata      ),
    .lb_rdata       (lb_rdata_1    ),
    .lb_rvalid      (lb_rvalid     ),
    .mac_status     (mac_status    )
);

// ---------------------------------
// Zest Digitizer Board Support
// ---------------------------------
`ifndef DSP_FREQ_MHZ
`define DSP_FREQ_MHZ 115.0
`endif

`ifndef DAC_INTERP_COEFF_R
`define DAC_INTERP_COEFF_R 1.0
`endif

zest #(
    .DSP_FREQ_MHZ   (`DSP_FREQ_MHZ),
    .DAC_INTERP_COEFF_R (`DAC_INTERP_COEFF_R),
    .BASE_ADDR      (8'h05)
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

/// #define PIN_I2C_SDA              0
/// #define PIN_I2C_SCL              1
/// #define PIN_PCA9548_RST          2
assign I2C_SDA      = gpio_z[0];
assign I2C_SCL      = gpio_z[1];
assign I2C_RST      = gpio_z[2]; // to enable I2C mux, set high

assign PMOD1 = {mac_status};
assign PMOD2 = {trap, gpio_z[30:24]};

endmodule
