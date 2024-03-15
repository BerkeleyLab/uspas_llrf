module timing_core #(
    parameter TEST_EVG = 0,
    parameter LB_CLK_FREQ = 125000000,
    parameter HARMONIC_N = 304, // Must be divisible by 4
    parameter DSP_EV1 = 1, // Configurable event code to route to dsp_clk.
    parameter DSP_EV2 = 2  // N.B: 0 is not a valid event code
) (
    // Fiber interface
    input             evg_clk, // Tie to 1'b0 if unused
    output [15:0]     evg_txd,
    output [1:0]      evg_txk,

    input             evr_clk,
    input [15:0]      evr_rxd,
    input [1:0]       evr_rxk,

    // EVG Control interface (@lb_clk)
    input             lb_clk,
    input [7:0]       evg_evcode, // external single-cycle; ignored if TEST_EVG disabled

    // EVR Control interface (@lb_clk)
    input [31:0]      evr_evmask, // external; Just lower 32 event codes for now
    input [6:0]       evr_oc_delay, // external; $clog2(HARMONIC_N/4)
    output [15:0]     evr_evcnt,
    output [2:0]      evr_sync_status, // 0: Orbit Clock synchronized
                                       // 1: HeartBeat valid
                                       // 2: PPS valid
    output            evr_timestamp_valid,
    output [27:0]     evr_clk_frequency,

    // To LLRF system (@dsp_clk). N.B: Assumes 12/11 relation between fEVR and fDSP
    input             dsp_clk,
    output            dsp_orbit,
    output [63:0]     dsp_orbit_ts,
    output [63:0]     dsp_live_ts,
    output [31:0]     dsp_live_pps_tick, // Expected to remain stable around the number of evr_clk in a PPS
    output            dsp_event1, // DSP_EV1
    output            dsp_event2,  // DSP_EV2
    output            phase_ramp_wave,
    output [63:0]     phase_ramp_ts
);

    // ---------------------
    // Measure and report recovered clock
    // ---------------------
    freq_count #(.refcnt_width (24), .freq_width (28)) fcnt_evr_clk (
        .sysclk     (lb_clk),
        .f_in       (evr_clk),
        .frequency  (evr_clk_frequency));


    // ---------------------
    // Timing Event Receiver (EVR)
    // ---------------------
    localparam EVR_EVSTROBE_CNT = 126; // As large as the highest event code of interest
    localparam EVR_TSTAMP_WI = 64;
    wire evr_pps_marker, evr_ts_valid_x;
    wire [EVR_TSTAMP_WI-1:0] evr_timestamp;
    wire [EVR_EVSTROBE_CNT-1:0] evr_evstrobe;

    tinyEVR #(.EVSTROBE_COUNT(EVR_EVSTROBE_CNT)) tinyEVR (
        .evrRxClk       (evr_clk),
        .evrRxWord      (evr_rxd),
        .evrCharIsK     (evr_rxk),
        .ppsMarker      (evr_pps_marker),
        .timestampValid (evr_ts_valid_x),
        .timestamp      (evr_timestamp),
        .evStrobe       (evr_evstrobe)
    );

    reg evr_ts_valid=0;
    always @(posedge lb_clk) evr_ts_valid <= evr_ts_valid_x; // Quasi-static
    assign evr_timestamp_valid = evr_ts_valid;

    // Event masking and counting in evr_clk domain
    reg [15:0] evr_evcnt_x=0;
    wire [31:0] evr_evstb_masked = evr_evstrobe[31:0] & ~evr_evmask; // evr_evmask is quasi-static

    // Start latching events only after timestamp has been recovered successfully to avoid registering
    // partially-decoded events
    always @(posedge evr_clk) if (|evr_evstb_masked && evr_ts_valid_x) evr_evcnt_x <= evr_evcnt_x + 1;

    // CDC to lb_clk
    data_xdomain #(.size(16)) i_evcnt_sync (
        .clk_in   (evr_clk), .gate_in  (1'b1),
        .data_in  (evr_evcnt_x),
        .clk_out  (lb_clk), .gate_out (),
        .data_out (evr_evcnt)
    );

    // Make configurable events available to LLRF in dsp_clk domain
    `ifdef SIMULATE
        initial if ((DSP_EV1 == 0) || (DSP_EV2 == 0)) begin
            $display("ERROR %m: Event code must be > 0");
            $finish;
        end
    `endif

    // Note -1 to go from event code to array index
    flag_xdomain i_ev1 (.clk1(evr_clk), .flagin_clk1(evr_evstrobe[DSP_EV1-1]),
                        .clk2(dsp_clk), .flagout_clk2(dsp_event1));
    flag_xdomain i_ev2 (.clk1(evr_clk), .flagin_clk1(evr_evstrobe[DSP_EV2-1]),
                        .clk2(dsp_clk), .flagout_clk2(dsp_event2));
   // Phase ramp timestamp and trigger
   data_xdomain #(.size(EVR_TSTAMP_WI)) phase_ramp_sync (
        .clk_in   (evr_clk), .gate_in  (evr_evstrobe[DSP_EV1-1]),
        .data_in  (evr_timestamp),
        .clk_out  (dsp_clk), .gate_out (phase_ramp_wave),
        .data_out (phase_ramp_ts)
    );

    // ---------------------
    // Orbit clock recovery
    // ---------------------
    // Based on heartbeat event (121);
    // Validates PPS and Heartbeat events by testing that they're close to 1 Hz in the
    // destination clock domain
    localparam HB_EV_NUM = 121;
    wire evr_hb_event = evr_evstrobe[HB_EV_NUM];

    wire evr_hb_valid, evr_pps_valid, evr_OC_valid, evr_OC;

    evrSROC #(
    `ifdef SIMULATE
        .SYSCLK_FREQUENCY(LB_CLK_FREQ/65600), // Frequency down-scaling to match fake EVG_HB_PERIOD
                                              // in g_evg
    `else
        .SYSCLK_FREQUENCY(LB_CLK_FREQ),
    `endif
        .SROC_DIVIDER(HARMONIC_N/4))
    i_evrAROC (
        .sysClk                  (lb_clk),
        .evrClk                  (evr_clk),
        .evrHeartbeatMarker      (evr_hb_event),
        .evrPulsePerSecondMarker (evr_pps_marker),

        .heartBeatValid          (evr_hb_valid),
        .pulsePerSecondValid     (evr_pps_valid),
        .evrSROCsynced           (evr_OC_valid),
        .evrSROC                 (evr_OC)
    );
    assign evr_sync_status = {evr_pps_valid, evr_hb_valid, evr_OC_valid};

    // ---------------------
    // Live timestamp and orbit clock trigger
    // ---------------------
    // Orbit clock is simply synchronized (after an optional delay) to dsp_clk domain alongside the
    // exact timestamp derived from the timing stream. The synchronization delay is variable, but
    // predictable, and depends on where the orbit clock rising-edge falls w.r.t dsp_clk

    reg evr_OC_r=0;
    always @(posedge evr_clk) evr_OC_r  <= evr_OC;
    wire evr_OC_trig_l = evr_OC & ~evr_OC_r;

    // Optionally delay OC_trig and pick right timestamp in evr_clk domain
    reg [6:0] evr_OC_cnt=0;

    wire evr_OC_trig_dly = (evr_OC_cnt == evr_oc_delay);
    always @(posedge evr_clk) begin
        if (evr_OC_trig_l) evr_OC_cnt <= evr_OC_cnt + 1;
        if (evr_OC_trig_dly) evr_OC_cnt <= 0;
    end

    wire evr_OC_trig = (evr_oc_delay==0) ? evr_OC_trig_l : evr_OC_trig_dly;

    data_xdomain #(.size(EVR_TSTAMP_WI)) i_oc_sync (
        .clk_in   (evr_clk), .gate_in  (evr_OC_trig),
        .data_in  (evr_timestamp),
        .clk_out  (dsp_clk), .gate_out (dsp_orbit),
        .data_out (dsp_orbit_ts)
    );

    // Maintain live timestamp by crossing PPS from evr_clk to dsp_clk and keeping a running tally
    // of event ticks since last PPS in that domain. Adjust count by +1 after every 11 cycles to
    // avoid drift from evr_clk tally, based on 12/11 relationship between evr_clk and dsp_clk. For
    // this to hold, both clocks must be derived from a common source.

    wire dsp_pps_marker;
    wire [31:0] dsp_pps;
    data_xdomain #(.size(EVR_TSTAMP_WI/2)) i_pps_sync (
        .clk_in   (evr_clk), .gate_in  (evr_pps_marker),
        .data_in  (evr_timestamp[63:32]),
        .clk_out  (dsp_clk), .gate_out (dsp_pps_marker),
        .data_out (dsp_pps)
    );

    reg [3:0] mod11=0;
    reg [31:0] dsp_tick=0;
    reg [31:0] dsp_tick_err;
    always @(posedge dsp_clk) begin
        dsp_tick <= dsp_tick + 1;
        mod11    <= mod11 + 1;
        if (mod11 == 10) begin
            dsp_tick <= dsp_tick + 2;
            mod11 <= 0;
        end
        if (dsp_pps_marker) begin
            dsp_tick <= 2; // Minimum delay to cross PPS to dsp_clk
            mod11 <= 0;
            dsp_tick_err <= dsp_tick;
        end
    end

    assign dsp_live_ts = {dsp_pps, dsp_tick};
    assign dsp_live_pps_tick = dsp_tick_err;

    // ---------------------
    // Optional Timing Event Generator (EVG) for testing purposes
    // ---------------------
    generate if (TEST_EVG) begin: g_evg
        // Barebones instantiation of a tinyEVG to allow loopback testing
        `ifdef SIMULATE
        reg [10:0] evg_pps_cnt = 0; // Faster wrapping for simulation (EVG debounce circuit uses timeout
                                    //  of 10 us)
        localparam EVG_HB_PERIOD = 76*25;
        `else
        reg [26:0] evg_pps_cnt = 0; // Roughly 1 sec
        localparam EVG_HB_PERIOD = 124640000; // Also roughly 1 sec
        `endif
        wire       evg_pps_marker = &evg_pps_cnt;
        reg [31:0] evg_seconds = 0;
        reg [31:0] evg_heartbeatInterval = 0;

        always @(posedge evg_clk) begin
            evg_pps_cnt <= &evg_pps_cnt ? 0 : evg_pps_cnt + 1;
            if (evg_pps_marker) evg_seconds <= evg_seconds + 1;
            evg_heartbeatInterval <= EVG_HB_PERIOD; // Register as a workaround to force internal EVG
                                                    // counter to reset to 0
        end

        // Detect changes in evg_evcode to generate accompanying strobe and simplify control interface
        reg [7:0] evg_evcode_r=0;
        wire [7:0] evg_evcode_x;
        wire evg_evcode_stb, evg_evcode_stb_x;

        // Rely on 'single-cycle' to detect and latch event writes
        always @(posedge lb_clk) evg_evcode_r <= evg_evcode;
        assign evg_evcode_stb = (evg_evcode != evg_evcode_r) && evg_evcode_r==0;

        data_xdomain #(.size(8)) i_evgcode_sync (
            .clk_in   (lb_clk), .gate_in  (evg_evcode_stb),
            .data_in  (evg_evcode),
            .clk_out  (evg_clk), .gate_out (evg_evcode_stb_x),
            .data_out (evg_evcode_x)
        );

        tinyEVG tinyEVG (
            // Connection to transmitter
            .evgTxClk  (evg_clk),
            .evgTxWord (evg_txd),
            .evgTxIsK  (evg_txk),
            .heartbeatInterval (evg_heartbeatInterval),

            // Arbitrary event requests
            .distributedBus    (8'b0),
            .eventCode         (evg_evcode_x),
            .eventStrobe       (evg_evcode_stb_x),

            .ppsMarker_a       (evg_pps_marker),
            .ppsToggle         (),
            .seconds_a         (evg_seconds)
        );
    end endgenerate

endmodule
