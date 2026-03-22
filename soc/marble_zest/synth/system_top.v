`timescale 1 ns / 1 ns

module system_top (
	input           GTPREFCLK_P,
	input           GTPREFCLK_N,

    inout [7:0]     PMOD1,
    inout [7:0]     PMOD2,

    inout           I2C_SCL,
    inout           I2C_SDA,
    output          I2C_RST,

    input           UART_CTS,
    output          UART_TX,
    input           UART_RX,

    // U24 74LVC8T245
    output          ZEST_ADC_PDWN,
    output          ZEST_ADC_CSB_0,
    output          ZEST_ADC_SYNC,
    output          ZEST_SCLK,       // ADC0, ADC1, DAC
    output          ZEST_SDI,        // LMK, DAC_SDIO
    output          ZEST_ADC_CSB_1,
    // U25 74LVC8T245
    output          ZEST_LMK_LEUWIRE,
    output          ZEST_PWR_SYNC,
    output          ZEST_PWR_EN,
    output          ZEST_AD7794_FCLK,
    // U26 74LVC8T245
    output          ZEST_DAC_CSB,
    output          ZEST_AMC7823_SPI_SS,
    output          ZEST_AD7794_CSB,
    output          ZEST_DAC_RESET,
    output          ZEST_POLL_SCLK,  // AMC7823, AD7794
    output          ZEST_POLL_MOSI,  // AMC7823, AD7794
    // U27 74LVC8T245
    output          ZEST_ADC_SDIO_DIR,
    inout           ZEST_ADC_SDIO,   // ADC0, ADC1
    // U28 74LVC8T245
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
    inout [7:0]     ZEST_PMOD2
);

parameter LB_READ_DELAY=3;
parameter LB_ADW = 20;
parameter FCNT_WIDTH = 16;
parameter PH_DIFF_DW = 13;
// Combine the 2 reset sources (USB, button)
wire clk;
wire clk_200;
wire clk_locked;

wire gtpclk0, gtpclk;
IBUFDS_GTE2 passi_125(.I(GTPREFCLK_P), .IB(GTPREFCLK_N), .CEB(1'b0), .O(gtpclk0));

// UG472 Figure 1-4
BUFH passg_125(
    .I(gtpclk0), .O(gtpclk)
);

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
    .clk_out0 (clk),
    .clk_out1 (clk_200),
    .locked   (clk_locked)
);

wire idelay_reset = ~clk_locked;
IDELAYCTRL idelayctrl_inst (
  .RST        (idelay_reset ),
  .REFCLK     (clk_200      ),
  .RDY        (idelayctrl_ready)
);

reg uart_cts1=0;
always @(posedge clk) uart_cts1 <= UART_CTS;
wire uart_cts_r = UART_CTS & ~uart_cts1;
// keep system in reset before idelayctrl is ready
wire reset_system = uart_cts_r | ~idelayctrl_ready;

// localbus master
reg lb0_write=0;
reg lb0_read=0;
reg [LB_ADW-1:0] lb0_addr=0;
reg [31:0] lb0_wdata=0;
wire [31:0] lb0_rdata;
reg lb0_rvalid=0;

// merged localbus master
wire lb_write;
wire lb_read;
wire lb_rvalid;
wire [LB_ADW-1:0] lb_addr;
wire [31:0] lb_wdata;
reg [31:0] lb_rdata = 0;

wire rst;
wire [68:0]       mem_packed_fwd;
wire [32:0]       mem_packed_ret;
wire trap;
system #(
    .LB_READ_DELAY(LB_READ_DELAY),
    .SYSTEM_HEX_PATH("./system32.dat")
) system_inst (
    .clk            (clk),
    .cpu_reset      (reset_system),
    .I2C_SCL        (I2C_SCL),
    .I2C_SDA        (I2C_SDA),
    .I2C_RST        (I2C_RST),
    .PMOD0          (PMOD1),
    .PMOD1          (PMOD2),
    .PMOD2          (ZEST_PMOD1),
    .PMOD3          (ZEST_PMOD2),
    .trig_to_dsp    (),
    .uart_tx        (UART_TX),
    .uart_rx        (UART_RX),
    .trap           (trap ),
    .lb_write       (lb0_write),
    .lb_read        (lb0_read),
    .lb_addr        (lb0_addr),
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

// LB read mux: Match READ_DELAY=3 in system.v
always @(posedge clk) casex(lb_addr[7:0])
    8'h0x:   lb_rdata <= 32'hdeadbeaf;
    8'h10:   lb_rdata <= 32'h10;
    default: lb_rdata <= 32'h0;
endcase

wire        dsp_clk_out;
wire        dac_clk_out;
wire [1:0]  clk_div_out;
wire [16*8-1:0] adc_out_data;
wire [7:0]  adc_out_clk;
wire [32:0] mem_packed_ret_0;
wire [13:0] dac_in_data_i;
wire [13:0] dac_in_data_q;

zest #(
    .DSP_FREQ_MHZ   (`DSP_FREQ_MHZ),
    .FCNT_WIDTH     (FCNT_WIDTH),
    .PH_DIFF_DW     (PH_DIFF_DW)
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

    .dsp_clk_out    (dsp_clk_out),
    .clk_div_out    (clk_div_out),
    .adc_out_clk    (adc_out_clk),
    .adc_out_data   (adc_out_data),
    .dac_clk_out    (dac_clk_out),
    .dac_in_data_i  (dac_in_data_i),
    .dac_in_data_q  (dac_in_data_q),

    .clk_200        (clk_200       ),
    .clk            (clk           ),
    .rst            (rst           ),
    .mem_packed_fwd (mem_packed_fwd),
    .mem_packed_ret (mem_packed_ret_0)
);

assign mem_packed_ret = mem_packed_ret_0;
endmodule
