module llrf_skin #(
    parameter N_ADC = 8,
    parameter LB_ADW = 18,
    parameter DW = 16
) (
    // ---------------------
    // Localbus interface
    // ---------------------
    input                lb_clk,
    input [LB_ADW-1:0]   lb_addr,
    input                lb_write,
    input                lb_read,
    input                lb_rvalid,
    input [31:0]         lb_wdata,
    output [31:0]        lb_rdata,
    input                lb_prefill,

    // ---------------------
    // Digitizer interface
    // ---------------------
    input                dsp_clk,
    input [DW*N_ADC-1:0] adc_data_in,
    output [DW-1:0]      dac_data_a_out,
    output [DW-1:0]      dac_data_b_out,

    // ---------------------
    // FO Interlock interface
    // ---------------------
    input                drive_permit_in,  // From RF Drive Control
    input                slow_permit_in,   // From Master Interlock PLC
    output               fast_permit_out,  // To Master Interlock PLC, RF Drive Control
    output               hpa_permit_out,   // To HPA

    // ---------------------
    // ARC Interlock interface
    // ---------------------
    input [2:0]          arc_permit_in,
    output [2:0]         arc_test_out,
    output               arc_reset_out,

    // ---------------------
    // MRF Fiber interface
    // ---------------------
`ifdef TEST_EVG
    output               evg_permit_out,   // To MRF EVG
    input                evg_tx_out_clk,
    output [15:0]        evg_txd,
    output [1:0]         evg_txk,
`endif

`ifdef TEST_EVR
    input                evr_rx_out_clk,
    input [15:0]         evr_rxd,
    input [1:0]          evr_rxk,
    input                evr_pll_locked
`endif

    output               trig_out
);


// Localbus
(* magic_cdc *) reg [LB_ADW-1:0]  lb_addr_r=0;
(* magic_cdc *) reg lb_write_r=0, lb_read_r=0, lb_rvalid_r=0;
(* magic_cdc *) reg [31:0]        lb_wdata_r=0;
(* magic_cdc *) reg [31:0]        lb_rdata_r=0;
/*           */ wire [31:0]       lb_rdata_x;
(* magic_cdc *) reg               lb_prefill_r=0;
always @(posedge lb_clk) begin
	lb_addr_r <= lb_addr;
	lb_write_r <= lb_write;
	lb_read_r <= lb_read;
	lb_rvalid_r <= lb_rvalid;
	lb_wdata_r <= lb_wdata;
	lb_rdata_r <= lb_rdata_x;
    lb_prefill_r <= lb_prefill;
end
assign lb_rdata = lb_rdata_r;

// Digitizer
(* magic_cdc *) reg [DW*N_ADC-1:0] adc_data_in_r=0;
always @(posedge dsp_clk) adc_data_in_r <= adc_data_in;

// MRF
`ifdef TEST_EVR
(* magic_cdc *) reg [15:0] evr_rxd_r=0;
(* magic_cdc *) reg [1:0] evr_rxx_r=0;
always @(posedge evr_rx_out_clk) begin
	evr_rxd_r <= evr_rxd;
	evr_rxx_r <= evr_rxx;
end
`endif

(* magic_cdc *) reg drive_permit_in_r=0;
(* magic_cdc *) reg slow_permit_in_r=0;
(* magic_cdc *) reg [2:0] arc_permit_in_r=0;
always @(posedge dsp_clk) begin
	drive_permit_in_r <= drive_permit_in;
	slow_permit_in_r <= slow_permit_in;
	arc_permit_in_r <= arc_permit_in;
end

`ifndef GIT_32BIT_ID
`define GIT_32BIT_ID 32'hdeadf00d
`endif

llrf_shell #(.GIT_REV_ID(`GIT_32BIT_ID), .CBUF_AW(11)) dsp (
    .lb_clk         (lb_clk),
    .lb_addr        (lb_addr_r),
    .lb_write       (lb_write_r),
    .lb_read        (lb_read_r),
    .lb_rvalid      (lb_rvalid_r),
    .lb_wdata       (lb_wdata_r),
    .lb_rdata       (lb_rdata_x),
    .lb_prefill     (lb_prefill_r),

    .dsp_clk        (dsp_clk),
    .adc_data_in    (adc_data_in_r),
    .dac_data_a_out (dac_data_a_out),
    .dac_data_b_out (dac_data_b_out),

    .drive_permit_in (drive_permit_in_r),
    .slow_permit_in  (slow_permit_in_r),
    .fast_permit_out (fast_permit_out),
    .hpa_permit_out  (hpa_permit_out),

    .arc_permit_in  (arc_permit_in_r),
    .arc_test_out   (arc_test_out),
    .arc_reset_out  (arc_reset_out),

`ifdef TEST_EVG
    .evg_permit_out (evg_permit_out),
    .evg_tx_out_clk (gt0_tx_out_clk),
    .evg_txd        (gt0_txd),
    .evg_txk        (gt0_txk),
`endif

`ifdef TEST_EVR
    .evr_rx_out_clk (evr_rx_out_clk),
    .evr_rxd        (evr_rxd_r),
    .evr_rxk        (evr_rxk_r),
    .evr_pll_locked (evr_pll_locked),
`endif

    .trig_out       (trig_out)
);

endmodule
