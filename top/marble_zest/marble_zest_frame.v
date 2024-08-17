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
    input [7:0] gmii_rxd,
    input gmii_rx_dv,
    input gmii_rx_er,
    // GMII Output (Tx)
    input gmii_tx_clk,
    output [7:0] gmii_txd,
    output gmii_tx_en,
    output gmii_tx_er,
    //
    output          PHY_RSTN,
    //
    input           UART_CTS,
    output          UART_TX,
    input           UART_RX,
    // Mailbox SPI
    input           FPGA_SCK,
    input           FPGA_CSB,
    input           FPGA_PICO,
    output          FPGA_POCI,
    // Zest ADC
    input           dsp_clk_p,
    input [127:0]   adc_out_data_p,
    //
    input   gtx_refclk,
    output  in_use
);

wire idelayctrl_ready=1;
wire clk_locked=1;
wire clk = gmii_tx_clk;
// Won't simulate this feature anytime soon
wire QSFP2_RXN=0, QSFP2_RXP=0;

`include "marble_zest_mid.vh"

// Set clock domain of 8 x 16-bit ADC data
assign dsp_clk = dsp_clk_p;
(* magic_cdc *) reg [127:0] adc_out_data_r=0;
always @(posedge dsp_clk) adc_out_data_r <= adc_out_data_p;
assign adc_out_data = adc_out_data_r;

assign mem_packed_ret = 0;  // officially in lb_clk (picorv32) domain

endmodule
