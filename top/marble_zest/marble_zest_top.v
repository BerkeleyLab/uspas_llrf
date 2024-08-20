module marble_zest_top #(
    parameter IP ={8'd192, 8'd168, 8'd19, 8'd122},
    parameter MAC = 48'h00105ad155b2,
    parameter LB_READ_DELAY=3
) (
    // Marble
    input           SYSCLK_P,
    input           SYSCLK_N,

    input           GTXREFCLK_P,
    input           GTXREFCLK_N,
    // QSFP2 channel 3
    // XXX option to change this?
    input           QSFP2_RXN,
    input           QSFP2_RXP,

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

    // SPI boot flash programming port
    output          BOOT_CS_B,
    input           BOOT_MISO,
    output          BOOT_MOSI,

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

wire sysclk0, sysclk;
IBUFDS_GTE2 passi_125(
    .I(SYSCLK_P), .IB(SYSCLK_N), .CEB(1'b0), .O(sysclk0)
);
// UG472 Figure 1-4
BUFH passg_125(
    .I(sysclk0), .O(sysclk)
);

// Move to system.v?  Gack, no!
// Rather, push system.v towards being vendor-neutral and easily simulatable.
wire gmii_tx_clk, gmii_rx_clk;
xilinx7_clocks #(
    .DIFF_CLKIN("BYPASS"),
    .CLKIN_PERIOD(8),  // REFCLK = 125 MHz
    .MULT     (8),     // 125 MHz X 8 = 1 GHz on-chip VCO
    .DIV0     (8),     // 1 GHz / 8 = 125 MHz
    .DIV1     (5)      // 1 GHz / 5 = 200 MHz
) clocks_i(
    .sysclk_p (sysclk),
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

wire gtx_refclk;
IBUFDS_GTE2 refclk(
    .I(GTXREFCLK_P), .IB(GTXREFCLK_N), .CEB(1'b0), .O(gtx_refclk)
);

wire in_use;  // ignored in synthesis

// Don't let the name of this module fool you - it involves chip- and
// vendor-specific DDR I/O cells.  It's not portable, and simulating it
// is typically less than helpful.
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

// ---------------------------------
// Share code with simulation build
// Includes instantiation of system, llrf_shell, and marble_bsp.
`include "marble_zest_mid.vh"
// ---------------------------------

// ---------------------------------
// Zest Digitizer Board Support
// ---------------------------------
`ifndef DSP_FREQ_MHZ
`define DSP_FREQ_MHZ 115.0
`endif

zest #(
    .DSP_FREQ_MHZ       (`DSP_FREQ_MHZ),
    .DAC_INTERP_COEFF_R (`DAC_INTERP_COEFF_R),
    .BASE_ADDR          (8'h05)
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
