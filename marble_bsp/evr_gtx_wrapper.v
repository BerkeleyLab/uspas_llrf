module evr_gtx_wrapper #(
    parameter QSFP_WI = 16,
    parameter DEBUG  = "true"
) (
    input                    sys_clk,
    input                    gtx_refclk,

    input                    QSFP2_RXN,
    input                    QSFP2_RXP,

    (*mark_debug=DEBUG*) input soft_reset,
    (*mark_debug=DEBUG*) input rx_slide_req,

    output                   rx_bufg_outclk,
    (*mark_debug=DEBUG*) output rx_resetdone,
    (*mark_debug=DEBUG*) output rx_aligned,
    (*mark_debug=DEBUG*) output reg [QSFP_WI-1:0]     rxdata_good = 0,
    (*mark_debug=DEBUG*) output reg [(QSFP_WI/8)-1:0] rxcharisk_good = 0,
    output                   cpll_locked,
    output  [1:0]            rx_notintable
);

// unused ports,GTX IP core uses RX_STARTUP_FSM module to reset
// see MR #29 for more info
wire gt_rxreset = 0, cpll_reset = 0, rx_pmareset = 0;

// Receiver alignment detection
wire rx_fsm_reset_done, cpll_fbclklost;
wire [15:0] rxdata_out;
wire [1:0] rxdisperr_out, rxnotintable_out, rxcharisk_out;
localparam COMMAS_NEEDED = 60;
localparam COMMA_COUNTER_RELOAD = COMMAS_NEEDED - 1;
localparam COMMA_COUNTER_WIDTH = $clog2(COMMA_COUNTER_RELOAD+1) + 1;
(*mark_debug=DEBUG*) reg [COMMA_COUNTER_WIDTH-1:0] comma_counter =
                                                           COMMA_COUNTER_RELOAD;
wire rx_outclk, rx_usrclk;
wire rx_isaligned = comma_counter[COMMA_COUNTER_WIDTH-1];
// error when the rxcharisk_out MSB bit is set and rxdata_out[15:8] == 8'hBC
// Allow commas (SOF, EOP - special ones) in the MSB,
// since MRF can support the "data protocol" on the dbus
// see page 18 of the EVG MRF document
// TODO: maybe can get away with only ((rxnotintable_out != 0) ||
// (rxdisperr_out != 0)), but needs to be tested
wire data_err = (rxnotintable_out != 0) || (rxdisperr_out != 0) || ((rxdata_out[15:8] == 8'hBC) && rxcharisk_out[1]);
always @(posedge rx_usrclk) begin
    if (data_err) begin
        comma_counter <= COMMA_COUNTER_RELOAD;
    end
    else if (!rx_isaligned && rxcharisk_out[0] && (rxdata_out[7:0] == 8'hBC)) begin
        comma_counter <= comma_counter - 1;
    end
end

assign rx_aligned = rx_isaligned;
assign rx_notintable = rxnotintable_out;

(*ASYNC_REG="true"*) reg rx_slide_x = 0;
reg rx_slide_xx = 0, rx_slide_xxx = 0;
(*mark_debug=DEBUG*) reg rx_slide = 0;
always @(posedge rx_usrclk) begin
    rx_slide_x  <= rx_slide_req;
    rx_slide_xx <= rx_slide_x;
    rx_slide_xxx <= rx_slide_xx;
    rx_slide <= rx_slide_xx && !rx_slide_xxx;
end

// Pass event codes out, only when we are aligned
wire goodcode = (rx_isaligned && !data_err);
always @(posedge rx_usrclk) begin
    rxdata_good <= goodcode ? rxdata_out : 16'd0;
    rxcharisk_good <= rxcharisk_out;
end

`ifndef SIMULATE
`ifndef YOSYS
BUFG rx_bufg (.I(rx_outclk), .O(rx_usrclk));
assign rx_bufg_outclk = rx_usrclk;

evr_gtx evr_gtx_i (
    .sysclk_in(sys_clk), // input wire sysclk_in
    .soft_reset_rx_in(soft_reset), // input wire soft_reset_rx_in
    .dont_reset_on_data_error_in(1'b1), // input wire dont_reset_on_data_error_in
    .gt0_tx_fsm_reset_done_out(), // output wire gt0_tx_fsm_reset_done_out
    .gt0_rx_fsm_reset_done_out(rx_fsm_reset_done), // output wire gt0_rx_fsm_reset_done_out
    .gt0_data_valid_in(1'b1), // input wire gt0_data_valid_in

    //____________________________CHANNEL PORTS________________________________
    //------------------------------- CPLL Ports -------------------------------
    .gt0_cpllfbclklost_out   (cpll_fbclklost), // output wire gt0_cpllfbclklost_out
    .gt0_cplllock_out        (cpll_locked), // output wire gt0_cplllock_out
    .gt0_cplllockdetclk_in   (sys_clk), // input wire gt0_cplllockdetclk_in
    .gt0_cpllreset_in        (cpll_reset), // input wire gt0_cpllreset_in
    //------------------------ Channel - Clocking Ports ------------------------
    .gt0_gtrefclk0_in        (gtx_refclk), // input wire gt0_gtrefclk0_in
    .gt0_gtrefclk1_in        (1'b0), // input wire gt0_gtrefclk1_in
    //-------------------------- Channel - DRP Ports  --------------------------
    .gt0_drpaddr_in          (9'd0), // input wire [8:0] gt0_drpaddr_in
    .gt0_drpclk_in           (sys_clk), // input wire gt0_drpclk_in
    .gt0_drpdi_in            (16'd0), // input wire [15:0] gt0_drpdi_in
    .gt0_drpen_in            (1'b0), // input wire gt0_drpen_in
    .gt0_drpwe_in            (1'b0), // input wire gt0_drpwe_in
    //------------------------- Digital Monitor Ports --------------------------
    .gt0_dmonitorout_out     (), // output wire [7:0] gt0_dmonitorout_out
    //------------------- RX Initialization and Reset Ports --------------------
    .gt0_eyescanreset_in     (1'b0), // input wire gt0_eyescanreset_in
    .gt0_rxuserrdy_in        (1'b1), // input wire gt0_rxuserrdy_in
    //------------------------ RX Margin Analysis Ports ------------------------
    .gt0_eyescandataerror_out(), // output wire gt0_eyescandataerror_out
    .gt0_eyescantrigger_in   (1'b0), // input wire gt0_eyescantrigger_in
    //---------------- Receive Ports - FPGA RX Interface Ports -----------------
    .gt0_rxdata_out          (rxdata_out), // output wire [15:0] gt0_rxdata_out
    .gt0_rxusrclk_in         (rx_usrclk), // input wire gt0_rxusrclk_in
    .gt0_rxusrclk2_in        (rx_usrclk), // input wire gt0_rxusrclk2_in
    //---------------- Receive Ports - RX 8B/10B Decoder Ports -----------------
    .gt0_rxcharisk_out       (rxcharisk_out), // output wire [1:0] gt0_rxcharisk_out
    .gt0_rxdisperr_out       (rxdisperr_out), // output wire [1:0] gt0_rxdisperr_out
    .gt0_rxnotintable_out    (rxnotintable_out), // output wire [1:0] gt0_rxnotintable_out
    //------------------------- Receive Ports - RX AFE -------------------------
    .gt0_gtxrxp_in           (QSFP2_RXP), // input wire gt0_gtxrxp_in
    .gt0_gtxrxn_in           (QSFP2_RXN), // input wire gt0_gtxrxn_in
    //----------------- Receive Ports - RX Buffer Bypass Ports -----------------
    .gt0_rxphmonitor_out     (), // output wire [4:0] gt0_rxphmonitor_out
    .gt0_rxphslipmonitor_out (), // output wire [4:0] gt0_rxphslipmonitor_out
    //------------------- Receive Ports - RX Equalizer Ports -------------------
    .gt0_rxdfelpmreset_in    (1'b0), // input wire gt0_rxdfelpmreset_in
    .gt0_rxmonitorout_out    (), // output wire [6:0] gt0_rxmonitorout_out
    .gt0_rxmonitorsel_in     (2'b01), // input wire [1:0] gt0_rxmonitorsel_in
    //------------- Receive Ports - RX Fabric Output Control Ports -------------
    .gt0_rxoutclk_out        (rx_outclk), // output wire gt0_rxoutclk_out
    .gt0_rxoutclkfabric_out  (), // output wire gt0_rxoutclkfabric_out
    //----------- Receive Ports - RX Initialization and Reset Ports ------------
    .gt0_gtrxreset_in        (gt_rxreset), // input wire gt0_gtrxreset_in
    .gt0_rxpmareset_in       (rx_pmareset), // input wire gt0_rxpmareset_in
    //-------------------- Receive Ports - RX gearbox ports --------------------
    .gt0_rxslide_in          (rx_slide), // input wire gt0_rxslide_in
    //------------ Receive Ports -RX Initialization and Reset Ports ------------
    .gt0_rxresetdone_out     (rx_resetdone), // output wire gt0_rxresetdone_out
    //------------------- TX Initialization and Reset Ports --------------------
    .gt0_gttxreset_in        (1'b0), // input wire gt0_gttxreset_in

    //____________________________COMMON PORTS________________________________
    .gt0_qplloutclk_in(1'b0), // input wire gt0_qplloutclk_in
    .gt0_qplloutrefclk_in(1'b0) // input wire gt0_qplloutrefclk_in
);
`else
   // Should we set rx_bufg_outclk=0 before a reset?
   // In a yosys-compatible way?
   assign rx_bufg_outclk = gtx_refclk;
   assign rx_usrclk = gtx_refclk;
   // This test pattern doesn't _do_ anything useful.  Rather, it repesents
   // signals in the same clock domain as the actual Xilinx hard-silicon,
   // for the benefit of cdc_snitch.
   reg [21:0] fake_testpat=1;  // one rotating bit
   always @(posedge gtx_refclk) fake_testpat <= {fake_testpat[20:0], fake_testpat[0]};
   assign {rx_notintable, rxcharisk_out, rxdata_out} = fake_testpat;
`endif
`else
   assign rx_bufg_outclk = gtx_refclk;
   assign rx_usrclk = gtx_refclk;
`endif
endmodule
