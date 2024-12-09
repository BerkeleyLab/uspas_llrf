module evr_gtx_wrapper #(
    parameter DEBUG = "false",
    parameter integer COMMAS_NEEDED = 60,
    parameter integer CHECK_TIMEOUT = 125000  // 125e6 Hz * 1ms
) (
    input               sys_clk,
    input               gtx_refclk,

    input               evr_gtx_rxn,
    input               evr_gtx_rxp,

    // sys_clk domain
    (*mark_debug=DEBUG*) input               soft_reset,
    (*mark_debug=DEBUG*) output              rx_fsm_reset_done,
    (*mark_debug=DEBUG*) output              rx_aligned_sys,
    (*mark_debug=DEBUG*) output [31:0]       rx_reset_cnt,
    (*mark_debug=DEBUG*) input               rx_slide_req,

    // rx_usrclk domain
    output              rx_usrclk,
    output              rx_resetdone,
    output reg [15:0]   rxdata = 0,
    output reg [1:0]    rxcharisk = 0
);

// Receiver alignment detection
wire rx_aligned;
wire [15:0] rxdata_out;
wire [1:0] rxdisperr_out, rxnotintable_out, rxcharisk_out;

wire [1:0] comma_seen;
assign comma_seen[0] = rxcharisk_out[0] & (rxdata_out[0+:8] == 8'hBC);
assign comma_seen[1] = rxcharisk_out[1] & (rxdata_out[8+:8] == 8'hBC);

// error when the rxcharisk_out MSB bit is set and rxdata_out[15:8] == 8'hBC
// Allow commas (SOF, EOP - special ones) in the MSB,
// since MRF can support the "data protocol" on the dbus
// see page 18 of the [EVG MRF document](http://www.mrf.fi/dmdocuments/EVG-TREF-004.pdf)
wire data_err_comb = (rxnotintable_out != 0) | (rxdisperr_out != 0);
reg data_err=0; always @(posedge rx_usrclk) data_err <= data_err_comb;

(*mark_debug=DEBUG*) wire error_seen_sys, comma_seen_sys;
reg_tech_cdc error_seen_x (.I(data_err), .C(sys_clk), .O(error_seen_sys));
reg_tech_cdc comma_seen_x (.I(comma_seen[0]), .C(sys_clk), .O(comma_seen_sys));

(*mark_debug=DEBUG*) wire gt_soft_reset, gt_soft_reset_fsm;
evr_reset_fsm #(
    .COMMAS_NEEDED  (COMMAS_NEEDED),
    .CHECK_TIMEOUT  (CHECK_TIMEOUT)
) evr_reset_fsm_i (
    .clk            (sys_clk),
    .rst            (1'b0),
    .error_seen     (error_seen_sys),
    .comma_seen     (comma_seen_sys),
    .reset_done     (rx_fsm_reset_done),
    .reset_out      (gt_soft_reset_fsm),
    .ready_out      (rx_aligned_sys),
    .reset_out_cnt  (rx_reset_cnt)
);
// combine fsm reset output and soft_reset from control bus
assign gt_soft_reset = gt_soft_reset_fsm | soft_reset;

reg_tech_cdc rx_aligned_x (.I(rx_aligned_sys), .C(rx_usrclk), .O(rx_aligned));

(*ASYNC_REG="true"*) reg rx_slide_x = 0;
reg rx_slide_xx = 0, rx_slide_xxx = 0;
reg rx_slide = 0;
always @(posedge rx_usrclk) begin
    rx_slide_x  <= rx_slide_req;
    rx_slide_xx <= rx_slide_x;
    rx_slide_xxx <= rx_slide_xx;
    rx_slide <= rx_slide_xx && !rx_slide_xxx;
end

// Pass event codes out, only when we are aligned
always @(posedge rx_usrclk) begin
    rxdata <= rx_aligned ? rxdata_out : 16'd0;
    rxcharisk <= rxcharisk_out;
end

wire rx_outclk;
wire cpll_fbclklost;
wire cpll_locked;

`ifndef SIMULATE
`ifndef YOSYS
BUFG rx_bufg (.I(rx_outclk), .O(rx_usrclk));

evr_gtx evr_gtx_i (
    .sysclk_in                  (sys_clk),      // input wire sysclk_in
    .soft_reset_rx_in           (gt_soft_reset),// input wire soft_reset_rx_in
    .dont_reset_on_data_error_in(1'b1),         // input wire dont_reset_on_data_error_in
    .gt0_tx_fsm_reset_done_out  (),             // output wire gt0_tx_fsm_reset_done_out
    .gt0_rx_fsm_reset_done_out  (rx_fsm_reset_done), // output wire gt0_rx_fsm_reset_done_out
    .gt0_data_valid_in          (1'b1),         // input wire gt0_data_valid_in

    //____________________________CHANNEL PORTS________________________________
    //------------------------------- CPLL Ports -------------------------------
    .gt0_cpllfbclklost_out   (cpll_fbclklost),  // output wire gt0_cpllfbclklost_out
    .gt0_cplllock_out        (cpll_locked),     // output wire gt0_cplllock_out
    .gt0_cplllockdetclk_in   (sys_clk),         // input wire gt0_cplllockdetclk_in
    .gt0_cpllreset_in        (1'b0),            // input wire gt0_cpllreset_in
    //------------------------ Channel - Clocking Ports ------------------------
    .gt0_gtrefclk0_in        (gtx_refclk),      // input wire gt0_gtrefclk0_in
    .gt0_gtrefclk1_in        (1'b0),            // input wire gt0_gtrefclk1_in
    //-------------------------- Channel - DRP Ports  --------------------------
    .gt0_drpaddr_in          (9'd0),            // input wire [8:0] gt0_drpaddr_in
    .gt0_drpclk_in           (sys_clk),         // input wire gt0_drpclk_in
    .gt0_drpdi_in            (16'd0),           // input wire [15:0] gt0_drpdi_in
    .gt0_drpen_in            (1'b0),            // input wire gt0_drpen_in
    .gt0_drpwe_in            (1'b0),            // input wire gt0_drpwe_in
    //------------------------- Digital Monitor Ports --------------------------
    .gt0_dmonitorout_out     (),                // output wire [7:0] gt0_dmonitorout_out
    //------------------- RX Initialization and Reset Ports --------------------
    .gt0_eyescanreset_in     (1'b0),            // input wire gt0_eyescanreset_in
    .gt0_rxuserrdy_in        (1'b1),            // input wire gt0_rxuserrdy_in
    //------------------------ RX Margin Analysis Ports ------------------------
    .gt0_eyescandataerror_out(),                // output wire gt0_eyescandataerror_out
    .gt0_eyescantrigger_in   (1'b0),            // input wire gt0_eyescantrigger_in
    //---------------- Receive Ports - FPGA RX Interface Ports -----------------
    .gt0_rxdata_out          (rxdata_out),      // output wire [15:0] gt0_rxdata_out
    .gt0_rxusrclk_in         (rx_usrclk),       // input wire gt0_rxusrclk_in
    .gt0_rxusrclk2_in        (rx_usrclk),       // input wire gt0_rxusrclk2_in
    //---------------- Receive Ports - RX 8B/10B Decoder Ports -----------------
    .gt0_rxcharisk_out       (rxcharisk_out),   // output wire [1:0] gt0_rxcharisk_out
    .gt0_rxdisperr_out       (rxdisperr_out),   // output wire [1:0] gt0_rxdisperr_out
    .gt0_rxnotintable_out    (rxnotintable_out),// output wire [1:0] gt0_rxnotintable_out
    //------------------------- Receive Ports - RX AFE -------------------------
    .gt0_gtxrxp_in           (evr_gtx_rxp),     // input wire gt0_gtxrxp_in
    .gt0_gtxrxn_in           (evr_gtx_rxn),     // input wire gt0_gtxrxn_in
    //----------------- Receive Ports - RX Buffer Bypass Ports -----------------
    .gt0_rxphmonitor_out     (),                // output wire [4:0] gt0_rxphmonitor_out
    .gt0_rxphslipmonitor_out (),                // output wire [4:0] gt0_rxphslipmonitor_out
    //------------------- Receive Ports - RX Equalizer Ports -------------------
    .gt0_rxdfelpmreset_in    (1'b0),            // input wire gt0_rxdfelpmreset_in
    .gt0_rxmonitorout_out    (),                // output wire [6:0] gt0_rxmonitorout_out
    .gt0_rxmonitorsel_in     (2'b01),           // input wire [1:0] gt0_rxmonitorsel_in
    //------------- Receive Ports - RX Fabric Output Control Ports -------------
    .gt0_rxoutclk_out        (rx_outclk),       // output wire gt0_rxoutclk_out
    .gt0_rxoutclkfabric_out  (),                // output wire gt0_rxoutclkfabric_out
    //----------- Receive Ports - RX Initialization and Reset Ports ------------
    .gt0_gtrxreset_in        (1'b0),            // input wire gt0_gtrxreset_in
    .gt0_rxpmareset_in       (1'b0),            // input wire gt0_rxpmareset_in
    //-------------------- Receive Ports - RX gearbox ports --------------------
    .gt0_rxslide_in          (rx_slide),        // input wire gt0_rxslide_in
    //------------ Receive Ports -RX Initialization and Reset Ports ------------
    .gt0_rxresetdone_out     (rx_resetdone),    // output wire gt0_rxresetdone_out
    //------------------- TX Initialization and Reset Ports --------------------
    .gt0_gttxreset_in        (1'b0),            // input wire gt0_gttxreset_in

    //____________________________COMMON PORTS________________________________
    .gt0_qplloutclk_in       (1'b0),            // input wire gt0_qplloutclk_in
    .gt0_qplloutrefclk_in    (1'b0)             // input wire gt0_qplloutrefclk_in
);
`else  // `ifndef YOSYS
   // Should we set rx_usrclk=0 before a reset?
   // In a yosys-compatible way?
   assign rx_usrclk = gtx_refclk;
   // This test pattern doesn't _do_ anything useful.  Rather, it represents
   // signals in the same clock domain as the actual Xilinx hard-silicon,
   // for the benefit of cdc_snitch.
   reg [21:0] fake_testpat=1;  // one rotating bit
   always @(posedge gtx_refclk) fake_testpat <= {fake_testpat[20:0], fake_testpat[0]};
   assign {rxnotintable_out, rxcharisk_out, rxdata_out} = fake_testpat;
   // UG476 says RXRESETDONE in RXUSRCLK2 domain, and CPLLLOCK is async.
   assign {rx_resetdone, cpll_locked} = 2'b11;
   assign rxdisperr_out = 2'b0;
   assign rx_fsm_reset_done = 1;
`endif  // `ifndef YOSYS
`else   // `ifndef SIMULATE
   assign rx_usrclk = gtx_refclk;
   // fake rx fsm reset mockup to simulate gtx rx start up time
   reg [7:0] fake_fsm_cnt=8'd32;
   reg fake_fsm_active=0;
   assign rx_fsm_reset_done = fake_fsm_cnt >= 8'd32;
   always @(posedge sys_clk) begin
        if (rx_fsm_reset_done) fake_fsm_active <= 1'b0;
        if (gt_soft_reset) begin
            fake_fsm_active <= 1'b1;
            fake_fsm_cnt <= 0;
        end
        if (fake_fsm_active)
            fake_fsm_cnt <= fake_fsm_cnt + 1'd1;
   end
   reg [1:0] rxnotintable_out_reg = 2'b0;
   assign rxnotintable_out = rxnotintable_out_reg;
   assign rxdisperr_out = 2'b0;
   assign rxdata_out = (rxnotintable_out != 0) ? 16'hxxxx : rx_fsm_reset_done ? {8'h0, 8'hBC} : 0;
   assign rxcharisk_out = 2'b01;
`endif  // `ifndef SIMULATE
endmodule

// Simplified version to
// https://github.com/enjoy-digital/liteiclink/blob/master/liteiclink/serdes/clock_aligner.py
// except 8b10b and rx_start_fsm are included in transceiver IP. Check:
// from liteiclink.serdes.clock_aligner import BruteforceClockAligner
// from migen.fhdl.verilog import convert
// convert(BruteforceClockAligner(0b0101111100, 125e6)).write('clock_aligner.v')
module evr_reset_fsm #(
    parameter DEBUG = "false",
    parameter integer COMMAS_NEEDED = 60,
    parameter integer CHECK_TIMEOUT = 125000  // 125e6 Hz * 1ms
) (
    input clk,
    input rst,
    input error_seen,
    input comma_seen,
    input reset_done,
    output reg ready_out = 0,
    output reg [31:0] reset_out_cnt = 0,
    output reset_out
);
    // State encoding
    localparam  READY = 2'd0,
                RESET = 2'd1,
                CHECK = 2'd2;
    // State register
    (*mark_debug=DEBUG*) reg [1:0] state=CHECK;
    (*mark_debug=DEBUG*) reg [1:0] current_state=CHECK, next_state=CHECK;

    (*mark_debug=DEBUG*) reg [7:0] comma_cnt = 0;
    (*mark_debug=DEBUG*) reg [17:0] check_timeout_cnt=0; // time out counter to count up to 1ms (125e3)

    // Task to update state string for simulation only
    reg [8*7:1] state_string;
    task update_state_string;
        input [1:0] state;
        begin
            case (state)
                READY: state_string = "READY ";
                RESET: state_string = "RESET ";
                CHECK: state_string = "CHECK ";
                default: state_string = "UNKNOWN";
            endcase
        end
    endtask

    // State transition logic
    always @(posedge clk) begin
        if (rst) begin
            comma_cnt <= 8'd0;
            current_state <= CHECK;
        end else begin
            current_state <= next_state;
            if (current_state == RESET) begin
                comma_cnt <= 8'b0; // Reset comma counter in RESET state
                check_timeout_cnt <= 18'b0; // Reset timeout counter
            end else if (current_state == CHECK) begin
                if (comma_seen && comma_cnt < COMMAS_NEEDED) begin
                    comma_cnt <= comma_cnt + 1'd1;
                end
                if (check_timeout_cnt < CHECK_TIMEOUT) begin
                    check_timeout_cnt <= check_timeout_cnt + 1'd1;
                end
            end else begin
                check_timeout_cnt <= 18'b0; // Reset timeout counter in other states
            end
        end
    end

    // Next state logic
    always @(*) begin
        case (current_state)
            READY: begin
                if (error_seen)
                    next_state = RESET;
                else
                    next_state = READY;
            end
            RESET: begin
                if (reset_done)
                    next_state = CHECK;
                else
                    next_state = RESET;
            end
            CHECK: begin
                if ((comma_cnt == COMMAS_NEEDED) && reset_done)
                    next_state = READY;
                else if (check_timeout_cnt == CHECK_TIMEOUT)
                    next_state = RESET;
                else
                    next_state = CHECK;
            end
            default: begin
                next_state = RESET;
            end
        endcase
    end

    reg reset=1'b0, reset_delay=1'b0;
    // Output logic
    always @(posedge clk) begin
        state <= current_state;
        update_state_string(current_state);
        reset_delay <= reset;
        reset <= (current_state == RESET);
        ready_out <= (current_state == READY);
        reset_out_cnt <= reset_out_cnt + reset_out;
    end
    assign reset_out = reset & ~reset_delay;   // Strobe reset_out for 1 cycle
endmodule
