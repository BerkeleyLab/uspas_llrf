// LEMP llrf_shell (plan step 9c): the base shell's blocks (rx_chain with
// the beam voltage and current channels as DC, diag, loops, tx_chain) and
// the LEMP features of the LEMP branch (2e25cd9): fiducial selection
// (fiducial_int_gen), the trigger delay global_delay, four PMOD triggers,
// the per-loop phase shift, the DAC permit latch with fiducial re-arm, SSSB
// control and timing_core_local. Registers, status words and readback
// windows: uspas_llrf/regmap.py with designs/lemp/design.py.
module llrf_shell
    import llrf_shell_pkg::*;
    import llrf_shell_regmap_pkg::*;
#(
    parameter integer F_DSP_HZ = 125_000_000,  // dsp_clk frequency, sets the arc_inlk 0.5 s pulse
    parameter integer CBUF_DW = 24,
    parameter integer CBUF_AW = 16,
    parameter integer SIG_BUF_AW = MAP_SIG_BUF_AW,  // buffer depth; at most the map's windows (sim: less)
    parameter integer NI = 8,           // interlocks latched by interlock_wrapper
    parameter integer DSP_EV1 = 151,    // EVR event codes to dsp_clk: ACCL
    parameter integer DSP_EV2 = 152,    //   STBY
    parameter integer DSP_EV3 = 1,      //   fiducial
    parameter integer DSP_EV4 = 10,     //   TS1&4
    parameter integer FIDUCIAL_WINDOW = 23800,  // dsp clocks to collect ACCL/STBY after a fiducial (sim: less)
    localparam integer CIC_SHIFT_BASE = 7,
    localparam integer INLK_SHIFT_BASE = 11, // near 2*np.log2(CIC_BASE_PERIOD) + 2
    localparam integer MON_RW = 44           // must <= 44, see ccfilt.v:51
) (
    // Localbus interface
    input                lb_clk,
    input [LB_ADW-1:0]   lb_addr,
    input                lb_write,
    input                lb_read,
    input                lb_rvalid,
    input [31:0]         lb_wdata,
    output [31:0]        lb_rdata,
    input                lb_prefill,

    // Digitizer interface
    input                dsp_clk,
    input [DW*N_ADC-1:0] adc_data_in,
    input                dac_clk,
    output [DW-1:0]      dac_data_a_out,
    output [DW-1:0]      dac_data_b_out,

    // Interlock interface
    input                drive_permit_in,     // From RF Drive Control
    input                slow_permit_in,      // From Master Interlock PLC
    output               fast_permit_out,     // To RF Drive Control
    output               fast_rf_permit_out,  // To Master Interlock PLC
    output [0:0]         evg_permit_out,      // To EVG
    output [0:0]         hpa_permit_out,      // To HPA (Oscillation Protection)

    // ARC Interlock interface
    input [2:0]          arc_permit_in,
    output [2:0]         arc_test_out,
    output               arc_reset_out,

    output               trig_out,
    // GT transceiver interface
    input                gt_rxclk,
    input [15:0]         gt_rxdata,
    input [1:0]          gt_rxcharisk,

    // External trigger interface
    input                ext_trigger,

    // LEMP interlock (interlock_wrapper): RX LO and its reset, latched trips
    output               dds_reset_out,
    output [DWLO-1:0]    dds_cos,
    output [DWLO-1:0]    dds_sin,
    input  [NI-1:0]      intlk_latch_in,
    // PMOD triggers: modulator, SSSB, scope, spare
    output [3:0]         pmod_trigs,
    // SSSB (solid state sub-booster)
    input                sssb_alarm,
    input                sssb_rf_status,
    output               sssb_rf_switch_out,
    output               sssb_rst_out,
    // EVR events ACCL, STBY, fiducial, TS1&4 (dsp_clk strobes)
    output [3:0]         evr_events
);

// ---------------------
// Registers, status and readback
// ---------------------
cfg_lb_t cfg_lb;
cfg_dsp_t cfg_dsp;
cfg_dac_t cfg_dac;
status_lb_t status_lb;
status_dsp_t status_dsp;
wire [LB_ADW-1:0] lb_addr_d1;
wire xfer_snap;
wire [INLK_AW-1:0] inlk_amp_lo_addr, inlk_amp_hi_addr, inlk_inlk_mode_addr;
wire [15:0] inlk_amp_lo, inlk_amp_hi;
wire [1:0] inlk_inlk_mode;
wire [31:0] rd_circle_ready, rd_sig_buf_ready, rd_sig_iq_buf_ready, rd_slow;
wire [31:0] rd_mon_amp, rd_mon_phs, rd_fault_amp, rd_cbuf;
wire [31:0] rd_adc_buf [N_ADC];
wire [31:0] rd_sig_i_buf [N_CH];
wire [31:0] rd_sig_q_buf [N_CH];
wire [31:0] rd_amp_mod [N_DRIVE];   // modulation tables (loop_ctrl)
wire [31:0] rd_phs_mod [N_DRIVE];
wire [N_DRIVE-1:0] wr_amp_mod, wr_phs_mod;

llrf_shell_regs regs (
    .lb_clk(lb_clk), .lb_addr(lb_addr), .lb_write(lb_write), .lb_read(lb_read),
    .lb_wdata(lb_wdata), .lb_prefill(lb_prefill), .lb_rdata(lb_rdata), .lb_addr_d1(lb_addr_d1),
    .dsp_clk(dsp_clk), .dac_clk(dac_clk), .gt_rxclk(gt_rxclk),
    .cfg_lb(cfg_lb), .cfg_dsp(cfg_dsp), .cfg_dac(cfg_dac),
    .inlk_amp_lo_addr(inlk_amp_lo_addr), .inlk_amp_lo(inlk_amp_lo),
    .inlk_amp_hi_addr(inlk_amp_hi_addr), .inlk_amp_hi(inlk_amp_hi),
    .inlk_inlk_mode_addr(inlk_inlk_mode_addr), .inlk_inlk_mode(inlk_inlk_mode),
    .status_lb(status_lb), .status_dsp(status_dsp), .xfer_snap(xfer_snap),
    .rd_circle_ready(rd_circle_ready), .rd_sig_buf_ready(rd_sig_buf_ready),
    .rd_sig_iq_buf_ready(rd_sig_iq_buf_ready), .rd_slow(rd_slow),
    .rd_mon_amp(rd_mon_amp), .rd_mon_phs(rd_mon_phs), .rd_fault_amp(rd_fault_amp),
    .rd_adc_buf(rd_adc_buf), .rd_sig_i_buf(rd_sig_i_buf), .rd_sig_q_buf(rd_sig_q_buf),
    .rd_cbuf(rd_cbuf),
    .rd_amp_mod(rd_amp_mod), .rd_phs_mod(rd_phs_mod), .wr_amp_mod(wr_amp_mod), .wr_phs_mod(wr_phs_mod)
);

wire dsp_reset = cfg_dsp.dsp_reset;

// ---------------------
// RX
// ---------------------
adc_t adc [N_ADC];
bb_t sig_i_data [N_CH];  // to diag: ADC channels (monitor path), then drives
bb_t sig_q_data [N_CH];
bb_t rx_i [N_ADC], rx_q [N_ADC], mon_i [N_ADC], mon_q [N_ADC];
// ADC 6 and 7 are the beam voltage and current: DC on the monitor path (L1)
rx_chain #(.DC_CH_MASK(8'b1100_0000)) rx_chain (
    .dsp_clk         (dsp_clk),
    .dsp_reset       (dsp_reset),
    .adc_data_in     (adc_data_in),
    .dds_amplitude   (cfg_dsp.rx_dds_amplitude),
    .dds_phase_shift (cfg_dsp.rx_dds_phase_shift),
    .dds_phase_step  (cfg_dsp.rx_dds_phase_step),
    .dds_modulo      (cfg_dsp.rx_dds_modulo),
    .adc             (adc),
    .sig_i           (rx_i),
    .sig_q           (rx_q),
    .mon_i           (mon_i),
    .mon_q           (mon_q),
    .lo_cos          (dds_cos),
    .lo_sin          (dds_sin)
);
// XXX plan 9c question 3: dsp_reset (proposal) or 0 as on the LEMP branch
assign dds_reset_out = dsp_reset;

genvar ch;
generate for (ch = 0; ch < N_ADC; ch = ch + 1) begin: gen_rx
    assign sig_i_data[ch] = mon_i[ch];
    assign sig_q_data[ch] = mon_q[ch];
end endgenerate

// ---------------------
// Interlock IO
// ---------------------
wire [0:0] drive_permit_sync;
wire [0:0] slow_permit_sync;
reg_tech_cdc drive_permit_cdc (.C(dsp_clk), .I(drive_permit_in), .O(drive_permit_sync));
reg_tech_cdc slow_permit_cdc  (.C(dsp_clk), .I(slow_permit_in), .O(slow_permit_sync));

wire external_permit_in;    // external permit input
wire internal_permit_out;   // internal generated permit output
wire [0:0] inlk_arc_permit; // internal permit from power and arc protection
reg hpa_osc_permit = 1'b1;  // internal permit from HPA oscillation detection, XXX TODO

assign external_permit_in = cfg_dsp.ext_permit_bypass ? 1'b1 : (drive_permit_sync && slow_permit_sync);
assign hpa_permit_out = hpa_osc_permit;
assign internal_permit_out = hpa_osc_permit && inlk_arc_permit;
wire [0:0] sum_drive_enable = internal_permit_out && external_permit_in;

assign fast_permit_out = internal_permit_out;
assign fast_rf_permit_out = internal_permit_out;
// per-drive registers, to the loops block
wire [N_DRIVE-1:0] soft_drive_enable = {cfg_dsp.soft_drive1_enable, cfg_dsp.soft_drive0_enable};
wire [N_DRIVE-1:0] drv_pulse_mode = {cfg_dsp.drv1_pulse_mode, cfg_dsp.drv0_pulse_mode};
assign evg_permit_out = soft_drive_enable[0] && sum_drive_enable;  // XXX ALSU specific

// ---------------------
// Triggering logic
// ---------------------
wire wave_trig;
wire int_trig, ext_trig;  // dsp_clk domain
reg [31:0] trig_count = 0;

// external trigger, rising edge
wire ext_trigger_sync;
reg_tech_cdc trigx_0(.I(ext_trigger), .C(dsp_clk), .O(ext_trigger_sync));
reg ext_trigger_sync1 = 0;
always @(posedge dsp_clk) ext_trigger_sync1 <= ext_trigger_sync;
assign ext_trig = ext_trigger_sync & ~ext_trigger_sync1;

// internal trigger
reg [31:0] int_trig_cnt = 0;
assign int_trig = (int_trig_cnt == cfg_dsp.int_trigger_period - 1);
always @(posedge dsp_clk) begin
    int_trig_cnt <= (dsp_reset || int_trig) ? 0 : int_trig_cnt + 1'b1;
    trig_count <= dsp_reset ? 0 : trig_count + wave_trig;
end

// fiducial: fiducial_int_gen picks the ACCL or STBY event within a fiducial
// window and gives its trigger delay as global_delay (fiducial_sel 1), or
// wave_trig itself with no delay (fiducial_sel 0)
wire [3:0] evr_events_dsp;
wire fiducial_int_i;
wire [31:0] global_delay_i;
wire [27:0] acc_cycles, stb_cycles;  // lb_clk
fiducial_int_gen #(
    .EVENT_NUM       (4),
    .EV_ACCL         (DSP_EV1),
    .EV_STBY         (DSP_EV2),
    .CYCLE_COUNT_MAX (FIDUCIAL_WINDOW)
) fiducial_int_gen (
    .lb_clk          (lb_clk),
    .dsp_clk         (dsp_clk),
    .reset           (1'b0),
    .event_strobes   (evr_events_dsp),
    .event_sel       (cfg_dsp.event_sel),
    .trig_acc_delay  (cfg_dsp.trig_acc_delay),
    .trig_stb_delay  (cfg_dsp.trig_stb_delay),
    .fiducial_int    (fiducial_int_i),
    .global_delay    (global_delay_i),
    .acc_cycles      (acc_cycles),
    .stb_cycles      (stb_cycles)
);

reg fiducial_int = 0;
reg [31:0] global_delay = 0;
always @(posedge dsp_clk) begin
    fiducial_int <= cfg_dsp.fiducial_sel ? fiducial_int_i : wave_trig;
    global_delay <= cfg_dsp.fiducial_sel ? global_delay_i : 32'd0;
end

// XXX plan 9c question 1: EVR (3) has no event-code trigger here
// (timing_core_local); like the LEMP branch, it falls to the default
wire cbuf_sync;
reg wave_trig_i = 0;
always @(posedge dsp_clk) begin
    case (cfg_dsp.wave_trig_sel)
        WAVE_TRIG_INT:      wave_trig_i <= int_trig;
        WAVE_TRIG_EXT:      wave_trig_i <= ext_trig;
        WAVE_TRIG_SOFT:     wave_trig_i <= cfg_dsp.soft_trigger;
        WAVE_TRIG_MIXED:    wave_trig_i <= ext_trig | cfg_dsp.soft_trigger;
        WAVE_TRIG_FIDUCIAL: wave_trig_i <= fiducial_int;
        default:            wave_trig_i <= cbuf_sync;
    endcase
end

// trigger delay: global_delay
pulse_gen #(.AW(32)) trig_delay_gen (
    .clk        (dsp_clk),
    .trigger    (wave_trig_i),
    .start      (global_delay),
    .high_len   (32'd1),
    .stb_in     (1'b1),
    .res        (4'd0),
    .pulse_dval (wave_trig),
    .pulse_last (),
    .pulse_idx  (),
    .pulse_clk  ()
);
assign trig_out = wave_trig;

// Periodically pass the status to the lb_clk domain
reg [2:0] xcnt = 0;
wire dsp_tick = &xcnt;
always @(posedge dsp_clk) xcnt <= xcnt + 1'b1;

// ---------------------
// Diagnostics: signal buffers, cic_waves, RF power and ARC interlocks
// ---------------------
wire [63:0] evr_live_ts_dsp;
wire [31:0] sig_buf_count;
wire [N_CH-1:0] inlk_hi_lb, inlk_lo_lb, inlk_status_lb, first_fault_status_lb, inlk_latch_lb;
wire [0:0] inlk_permit_out_lb, arc_permit_sum_lb, arc_testing_lb;
wire [2:0] arc_permit_raw_lb, arc_permit_latch_lb;
diag #(
    .F_DSP_HZ        (F_DSP_HZ),
    .CBUF_DW         (CBUF_DW),
    .CBUF_AW         (CBUF_AW),
    .SIG_BUF_AW      (SIG_BUF_AW),
    .CIC_SHIFT_BASE  (CIC_SHIFT_BASE),
    .INLK_SHIFT_BASE (INLK_SHIFT_BASE),
    .MON_RW          (MON_RW)
) diag (
    .dsp_clk               (dsp_clk),
    .dsp_reset             (dsp_reset),
    .dsp_tick              (dsp_tick),
    .adc_data_in           (adc_data_in),
    .adc                   (adc),
    .sig_i                 (sig_i_data),
    .sig_q                 (sig_q_data),
    .wave_trig             (wave_trig),
    .buf_delay             (cfg_dsp.buf_delay),
    .cbuf_free_run         (cfg_dsp.wave_trig_sel == WAVE_TRIG_ALWAYS),
    .record_en             (sum_drive_enable),
    .evr_timestamp         (evr_live_ts_dsp),
    .wave_samp_per         (cfg_dsp.wave_samp_per),
    .chan_keep             (cfg_dsp.chan_keep),
    .cic_base_period       (cfg_dsp.cic_base_period),
    .cic_wave_shift        (cfg_dsp.cic_wave_shift),
    .inlk_wave_shift       (cfg_dsp.inlk_wave_shift),
    .cbuf_post_delay       (cfg_dsp.cbuf_post_delay),
    .dsp_tag               (cfg_dsp.dsp_tag),
    .slow_snap_cic         (cfg_dsp.slow_snap_cic),
    .inlk_cfg              (cfg_dsp.inlk),
    .arc_cfg               (cfg_dsp.arc),
    .inlk_amp_lo           (inlk_amp_lo),
    .inlk_amp_lo_addr      (inlk_amp_lo_addr),
    .inlk_amp_hi           (inlk_amp_hi),
    .inlk_amp_hi_addr      (inlk_amp_hi_addr),
    .inlk_inlk_mode        (inlk_inlk_mode),
    .inlk_inlk_mode_addr   (inlk_inlk_mode_addr),
    .arc_permit_in         (arc_permit_in),
    .arc_test_out          (arc_test_out),
    .arc_reset_out         (arc_reset_out),
    .cbuf_sync             (cbuf_sync),
    .inlk_arc_permit       (inlk_arc_permit),
    .sig_buf_count         (sig_buf_count),
    .lb_clk                (lb_clk),
    .lb_read               (lb_read),
    .lb_addr               (lb_addr),
    .lb_addr_d1            (lb_addr_d1),
    .sig_buf_flip          (cfg_lb.sig_buf_flip),
    .circle_buf_flip       (cfg_lb.circle_buf_flip),
    .rd_circle_ready       (rd_circle_ready),
    .rd_sig_buf_ready      (rd_sig_buf_ready),
    .rd_sig_iq_buf_ready   (rd_sig_iq_buf_ready),
    .rd_slow               (rd_slow),
    .rd_mon_amp            (rd_mon_amp),
    .rd_mon_phs            (rd_mon_phs),
    .rd_fault_amp          (rd_fault_amp),
    .rd_adc_buf            (rd_adc_buf),
    .rd_sig_i_buf          (rd_sig_i_buf),
    .rd_sig_q_buf          (rd_sig_q_buf),
    .rd_cbuf               (rd_cbuf),
    .inlk_hi_lb            (inlk_hi_lb),
    .inlk_lo_lb            (inlk_lo_lb),
    .inlk_status_lb        (inlk_status_lb),
    .first_fault_status_lb (first_fault_status_lb),
    .inlk_latch_lb         (inlk_latch_lb),
    .inlk_permit_out_lb    (inlk_permit_out_lb),
    .arc_permit_raw_lb     (arc_permit_raw_lb),
    .arc_permit_latch_lb   (arc_permit_latch_lb),
    .arc_permit_sum_lb     (arc_permit_sum_lb),
    .arc_testing_lb        (arc_testing_lb)
);

// ---------------------
// Timing module with EVR (LEMP: timing_core_local, four event codes)
// ---------------------
wire [15:0] evr_evcnt_lb;
wire [0:0]  evr_ts_valid_lb;
wire [28*4-1:0] evr_frequency_events_flat;  // lb_clk; [27:0] is event 4 (see timing_core_local)
timing_core_local #(
    .DSP_EV1 (DSP_EV1), .DSP_EV2 (DSP_EV2), .DSP_EV3 (DSP_EV3), .DSP_EV4 (DSP_EV4)
) timing_evr (
    .lb_clk                (lb_clk),
    .evr_clk               (gt_rxclk),
    .evr_rxd               (gt_rxdata),
    .evr_rxk               (gt_rxcharisk),
    .evr_evcnt             (evr_evcnt_lb),
    .evr_timestamp_valid   (evr_ts_valid_lb),
    .dsp_clk               (dsp_clk),
    .dsp_live_ts           (evr_live_ts_dsp),
    .dsp_pps_marker        (),
    .dsp_hb_marker         (),
    .evr_event1            (),
    .dsp_event1            (evr_events_dsp[0]),  // ACCL
    .dsp_event2            (evr_events_dsp[1]),  // STBY
    .dsp_event3            (evr_events_dsp[2]),  // fiducial
    .dsp_event4            (evr_events_dsp[3]),  // TS1&4
    .frequency_events_flat (evr_frequency_events_flat)
);
assign evr_events = evr_events_dsp;

// ---------------------
// DAC permit: any latched interlock clears both drives; with none latched,
// a fiducial rising edge re-arms them from soft_driveN_enable
// ---------------------
reg [N_DRIVE-1:0] dac_permit = '0;
reg fiducial_int_dly = 0;
always @(posedge dsp_clk) begin
    fiducial_int_dly <= fiducial_int;
    if (|intlk_latch_in) dac_permit <= '0;
    else if (fiducial_int & ~fiducial_int_dly) dac_permit <= soft_drive_enable;
end

// ---------------------
// Feedback loops with pulse modulation
// ---------------------
// XXX network analyzer setpoints bypassed for now
wire signed [DWBB-1:0] amp_setpoint_ntw;
wire signed [DWBB-1:0] phs_setpoint_ntw;

bb_t drive_i_out [N_DRIVE];
bb_t drive_q_out [N_DRIVE];
bb_t phs_offset [N_DRIVE];
wire [N_DRIVE-1:0] pulse_dval;
wire [PULSE_AW-1:0] pulse_clk [N_DRIVE];
wire signed [14:0] err_out_amp_lb [N_DRIVE];
wire signed [14:0] err_out_phs_lb [N_DRIVE];
// per-loop phase shift, from pulse clock loopN_phs_shift_delay to the pulse
// end (L5: no underflow when the delay exceeds the pulse); pulse_clk counts
// dsp clocks into the pulse whatever pulse_res_shift is (LEMP review)
wire signed [DWBB-1:0] phs_shift [N_DRIVE];
wire [31:0] phs_shift_delay [N_DRIVE];
assign phs_shift[0] = cfg_dsp.loop0_phs_shift;
assign phs_shift[1] = cfg_dsp.loop1_phs_shift;
assign phs_shift_delay[0] = cfg_dsp.loop0_phs_shift_delay;
assign phs_shift_delay[1] = cfg_dsp.loop1_phs_shift_delay;
generate for (ch = 0; ch < N_DRIVE; ch = ch + 1) begin: gen_drive
    assign phs_offset[ch] = (pulse_dval[ch] && pulse_clk[ch] >= phs_shift_delay[ch]) ? phs_shift[ch] : '0;
    // base-band loop output for IQ waveform monitoring
    assign sig_i_data[N_ADC+ch] = drive_i_out[ch];
    assign sig_q_data[N_ADC+ch] = drive_q_out[ch];
end endgenerate

loops loops (
    .dsp_clk         (dsp_clk),
    .dsp_reset       (dsp_reset),
    .dsp_tick        (dsp_tick),
    .cfg             (cfg_dsp.loop),
    .rx_phase_offset (cfg_dsp.rx_phase_offset),
    .tx_phase_offset (cfg_dsp.tx_phase_offset),
    .trig            (wave_trig),
    .pulse_mode      (drv_pulse_mode),
    .drive_permit    (dac_permit & {N_DRIVE{sum_drive_enable}}),
    .phs_offset      (phs_offset),
    .sig_i           (rx_i),
    .sig_q           (rx_q),
    .drive_i         (drive_i_out),
    .drive_q         (drive_q_out),
    .pulse_dval      (pulse_dval),
    .pulse_idx       (),
    .pulse_clk       (pulse_clk),
    .err_amp_lb      (err_out_amp_lb),
    .err_phs_lb      (err_out_phs_lb),
    .lb_clk          (lb_clk),
    .lb_addr         (lb_addr[MAP_MOD_AW-1:0]),
    .lb_wdata        (lb_wdata[DWBB-1:0]),
    .wr_amp_mod      (wr_amp_mod),
    .wr_phs_mod      (wr_phs_mod),
    .rd_amp_mod      (rd_amp_mod),
    .rd_phs_mod      (rd_phs_mod)
);

// ---------------------
// TX
// ---------------------
tx_chain tx_chain (
    .dsp_clk              (dsp_clk),
    .dsp_reset            (dsp_reset),
    .drive_i              (drive_i_out),
    .drive_q              (drive_q_out),
    .dac_clk              (dac_clk),
    .dds_amplitude        (cfg_dac.tx_dds_amplitude),
    .dds_phase_shift      (cfg_dac.tx_dds_phase_shift),
    .dds_phase_step       (cfg_dac.tx_dds_phase_step),
    .dds_modulo           (cfg_dac.tx_dds_modulo),
    .duc_spectral_flip    (cfg_dac.duc_spectral_flip),
    .tx_afe_spectral_flip (cfg_dac.tx_afe_spectral_flip),
    .dac_drive_sel        (cfg_dac.dac_drive_sel),
    .dac_data_a_out       (dac_data_a_out),
    .dac_data_b_out       (dac_data_b_out)
);

// ---------------------
// Network analyzer feature
// ---------------------
// XXX replace by dds.v
wire ntw_trig_i = (cfg_dsp.ntw_amp_enable || cfg_dsp.ntw_phs_enable) ? cbuf_sync : 0;
wire signed [17:0] ntw_cos_debug;
wire signed [18:0] ntw_phase_debug;
ntw_analyzer #(.KW(DWBB)) ntw (
    .clk              (dsp_clk),
    .trig             (ntw_trig_i),
    .ext_amp_enable   (cfg_dsp.ntw_amp_enable),
    .ext_phs_enable   (cfg_dsp.ntw_phs_enable),
    .amp_setpoint     (cfg_dsp.loop[0].amp_setpoint),
    .phs_setpoint     (cfg_dsp.loop[0].phs_setpoint),
    .ntw_phase_debug  (ntw_phase_debug),
    .ntw_cos_debug    (ntw_cos_debug),
    .amp_stp_ntw      (amp_setpoint_ntw), // final amplitude setpoint after excitation
    .phs_stp_ntw      (phs_setpoint_ntw),
    .cfg              (cfg_dsp.ntw)
);

// ---------------------
// PMOD triggers: restarted by the fiducial, global_delay + trig_N_delay
// after it; an interlock latch stops the modulator trigger (0)
// ---------------------
wire [3:0] trig_enable = {cfg_dsp.trig_enables[3:1], cfg_dsp.trig_enables[0] & ~|intlk_latch_in};
generate for (ch = 0; ch < 4; ch = ch + 1) begin: gen_trig
    triggers trig (
        .clk          (dsp_clk),
        .rst_n        (~fiducial_int),
        .enable       (trig_enable[ch]),
        .global_delay (global_delay),
        .cfg          (cfg_dsp.trig[ch]),
        .pmod_trigs   (pmod_trigs[ch])
    );
end endgenerate

// SSSB control, active low
assign sssb_rf_switch_out = ~cfg_dsp.sssb_rf_switch;
assign sssb_rst_out = ~cfg_dsp.sssb_rst;

wire [27:0] dsp_clk_frequency;  // lb_clk
freq_count #(.refcnt_width(24), .freq_width(28)) fcnt_dsp_clk (
    .sysclk    (lb_clk),
    .f_in      (dsp_clk),
    .frequency (dsp_clk_frequency),
    .freq_strobe (), .diff_stream (), .diff_stream_strobe (), .glitch_catcher ()
);

// ---------------------
// Status words
// ---------------------
assign status_lb.rf_pwr_hi = inlk_hi_lb;
assign status_lb.rf_pwr_lo = inlk_lo_lb;
assign status_lb.rf_pwr_status = inlk_status_lb;
assign status_lb.rf_pwr_first_fault_status = first_fault_status_lb;
assign status_lb.rf_pwr_latch = inlk_latch_lb;
assign status_lb.rf_pwr_permit_sum = inlk_permit_out_lb;
assign status_lb.arc_permit_raw = arc_permit_raw_lb;
assign status_lb.arc_permit_latch = arc_permit_latch_lb;
assign status_lb.arc_permit_sum = arc_permit_sum_lb;
assign status_lb.loop0_amp_err = err_out_amp_lb[0];
assign status_lb.loop0_phs_err = err_out_phs_lb[0];
assign status_lb.loop1_amp_err = err_out_amp_lb[1];
assign status_lb.loop1_phs_err = err_out_phs_lb[1];
assign status_lb.evr_evcnt = evr_evcnt_lb;
assign status_lb.evr_ts_valid = evr_ts_valid_lb;
assign status_lb.arc_testing = arc_testing_lb;
assign status_lb.dsp_clk_frequency = dsp_clk_frequency;
assign status_lb.sssb_alarm = sssb_alarm;
assign status_lb.sssb_rf_status = sssb_rf_status;
assign status_lb.evr_frequency_event1 = evr_frequency_events_flat[27:0];
assign status_lb.evr_frequency_event2 = evr_frequency_events_flat[55:28];
assign status_lb.evr_frequency_event3 = evr_frequency_events_flat[83:56];
assign status_lb.evr_frequency_event4 = evr_frequency_events_flat[111:84];
assign status_lb.acc_cycles = acc_cycles;
assign status_lb.stb_cycles = stb_cycles;

// Self-consistent readout of all 64 bits of evr_live_ts_dsp: the high word
// is latched when the dsp_clk status bank is snapshot (evr_live_ts_lo slot 0)
reg [31:0] evr_live_ts_hi = 0;
always @(posedge dsp_clk) if (xfer_snap) evr_live_ts_hi <= evr_live_ts_dsp[63:32];
assign status_dsp.evr_live_ts_lo = evr_live_ts_dsp[31:0];
assign status_dsp.evr_live_ts_hi = evr_live_ts_hi;
assign status_dsp.amp_setpoint_ntw = amp_setpoint_ntw;
assign status_dsp.phs_setpoint_ntw = phs_setpoint_ntw;
assign status_dsp.sig_buf_count = sig_buf_count;
assign status_dsp.ntw_cos_debug = ntw_cos_debug;
assign status_dsp.ntw_phase_debug = ntw_phase_debug;
assign status_dsp.trig_count = trig_count;
assign status_dsp.fast_permit_out = inlk_arc_permit;
assign status_dsp.drive_permit_in = drive_permit_sync;
assign status_dsp.slow_permit_in = slow_permit_sync;
assign status_dsp.evg_permit_out = evg_permit_out;
assign status_dsp.hpa_permit_out = hpa_permit_out;
assign status_dsp.drive_permit_out = sum_drive_enable;

endmodule
