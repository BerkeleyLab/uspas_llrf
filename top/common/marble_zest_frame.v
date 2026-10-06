// Simulation-friendly encapsulation of most of the final chip,
// stripped of vendor primitives, and unfortunately also leaving off everything to do with Zest.
// See topsim.cpp.
`timescale 1ns / 1ns
module marble_zest_frame #(
    parameter IP ={8'd192, 8'd168, 8'd7, 8'd123},
    parameter MAC = 48'h00105ad155b2,
    parameter LB_READ_DELAY=3
) (
    // GMII Input (Rx)
    input gmii_rx_clk,
    input [7:0] gmii_rxd_p,
    input gmii_rx_dv_p,
    input gmii_rx_er_p,
    // GMII Output (Tx)
    input gmii_tx_clk,
    output [7:0] gmii_txd,
    output gmii_tx_en,
    output gmii_tx_er,
    //
    output          PHY_RSTN,
    inout [7:0]     PMOD1,
    inout [7:0]     ZEST_PMOD2,
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
    // Zest ADC
    input           dsp_clk_p,
    input [127:0]   adc_out_data_p,
    // UART Rx results
    output          b_dv,
    output [7:0]    b_do,
    // UART Tx control
    input           b_we,
    input [7:0]     b_di,
    //
    input   gt_refclk,
    input   clk_200,
    output  in_use
);

// Define RGMII input as being in gmii_rx_clk domain
(* magic_cdc *) reg [7:0] gmii_rxd=0;
(* magic_cdc *) reg gmii_rx_dv=0, gmii_rx_er=0;
always @(posedge gmii_rx_clk) begin
    gmii_rxd <= gmii_rxd_p;
    gmii_rx_dv <= gmii_rx_dv_p;
    gmii_rx_er <= gmii_rx_er_p;
end
// UART Tx control uses gmii_tx_clk
(* magic_cdc *) reg [7:0] b_di_r;
(* magic_cdc *) reg b_we_r;
always @(posedge gmii_tx_clk) begin
    b_di_r <= b_di;
    b_we_r <= b_we;
end

wire idelayctrl_ready=1;
wire clk_locked=1;
wire clk = gmii_tx_clk;
// Won't simulate this feature anytime soon
wire MGT_RX_6_N=0, MGT_RX_6_P=0;
// UART below
wire UART_CTS, UART_RX, UART_TX;

`include "marble_zest_mid.vh"

// Set clock domain of 8 x 16-bit ADC data
assign dsp_clk = dsp_clk_p;
(* magic_cdc *) reg [127:0] adc_out_data_r=0;
always @(posedge dsp_clk) adc_out_data_r <= adc_out_data_p;
assign adc_out_data = adc_out_data_r;

assign mem_packed_ret = 0;  // officially in lb_clk (picorv32) domain

// Only hook up the (simulated) FPGA Tx to the debugging Rx device
reg uart_resetn=0;
always @(posedge gmii_tx_clk) uart_resetn <= 1;
simpleuart uart(.clk(gmii_tx_clk), .resetn(uart_resetn),
    .ser_rx(UART_TX), .ser_tx(UART_RX),
    .cfg_divider(20'd1085),  // 115200 baud
    .b_do(b_do), .b_dv(b_dv), .b_re(1'b1),   // results
    .b_we(b_we_r), .b_di(b_di_r)  // we can send, too
);
assign UART_CTS = 0;

endmodule
