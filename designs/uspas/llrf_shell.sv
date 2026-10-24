// Base llrf_shell (plan §2.1): the generated register file, the shared
// blocks (rx_chain, diag, tx_chain), and the design-owned permits, trigger
// selection, feedback loops, network analyzer and EVR timing.
// Registers, status words and readback windows: uspas_llrf/regmap.py.
module llrf_shell
    import llrf_shell_pkg::*;
    import llrf_shell_regmap_pkg::*;
#(
    parameter integer F_DSP_HZ = 125_000_000,  // dsp_clk frequency, sets the arc_inlk 0.5 s pulse
    parameter integer CBUF_DW = 24,
    parameter integer CBUF_AW = 16,
    parameter integer SIG_BUF_AW = MAP_SIG_BUF_AW,  // buffer depth; at most the map's windows (sim: less)
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
    input                ext_trigger
);

// ---------------------
// Registers, status and readback
// ---------------------
cfg_lb_t cfg_lb;
cfg_dsp_t cfg_dsp;
cfg_dac_t cfg_dac;
cfg_evr_t cfg_evr;
status_lb_t status_lb;
status_dsp_t status_dsp;
wire [LB_ADW-1:0] lb_addr_d1;
wire xfer_snap;
wire [3:0] inlk_amp_lo_addr, inlk_amp_hi_addr, inlk_inlk_mode_addr;
wire [15:0] inlk_amp_lo, inlk_amp_hi;
wire [1:0] inlk_inlk_mode;
wire [31:0] rd_circle_ready, rd_sig_buf_ready, rd_sig_iq_buf_ready, rd_slow;
wire [31:0] rd_mon_amp, rd_mon_phs, rd_fault_amp, rd_cbuf;
wire [31:0] rd_adc_buf [N_ADC];
wire [31:0] rd_sig_i_buf [N_CH];
wire [31:0] rd_sig_q_buf [N_CH];

llrf_shell_regs regs (
    .lb_clk(lb_clk), .lb_addr(lb_addr), .lb_write(lb_write), .lb_read(lb_read),
    .lb_wdata(lb_wdata), .lb_prefill(lb_prefill), .lb_rdata(lb_rdata), .lb_addr_d1(lb_addr_d1),
    .dsp_clk(dsp_clk), .dac_clk(dac_clk), .gt_rxclk(gt_rxclk),
    .cfg_lb(cfg_lb), .cfg_dsp(cfg_dsp), .cfg_dac(cfg_dac), .cfg_evr(cfg_evr),
    .inlk_amp_lo_addr(inlk_amp_lo_addr), .inlk_amp_lo(inlk_amp_lo),
    .inlk_amp_hi_addr(inlk_amp_hi_addr), .inlk_amp_hi(inlk_amp_hi),
    .inlk_inlk_mode_addr(inlk_inlk_mode_addr), .inlk_inlk_mode(inlk_inlk_mode),
    .status_lb(status_lb), .status_dsp(status_dsp), .xfer_snap(xfer_snap),
    .rd_circle_ready(rd_circle_ready), .rd_sig_buf_ready(rd_sig_buf_ready),
    .rd_sig_iq_buf_ready(rd_sig_iq_buf_ready), .rd_slow(rd_slow),
    .rd_mon_amp(rd_mon_amp), .rd_mon_phs(rd_mon_phs), .rd_fault_amp(rd_fault_amp),
    .rd_adc_buf(rd_adc_buf), .rd_sig_i_buf(rd_sig_i_buf), .rd_sig_q_buf(rd_sig_q_buf),
    .rd_cbuf(rd_cbuf)
);

wire dsp_reset = cfg_dsp.dsp_reset;

// ---------------------
// RX
// ---------------------
adc_t adc [N_ADC];
bb_t sig_i_data [N_CH];  // ADC channels, then drives
bb_t sig_q_data [N_CH];
bb_t rx_i [N_ADC], rx_q [N_ADC];
rx_chain rx_chain (
    .dsp_clk         (dsp_clk),
    .dsp_reset       (dsp_reset),
    .adc_data_in     (adc_data_in),
    .dds_amplitude   (cfg_dsp.rx_dds_amplitude),
    .dds_phase_shift (cfg_dsp.rx_dds_phase_shift),
    .dds_phase_step  (cfg_dsp.rx_dds_phase_step),
    .dds_modulo      (cfg_dsp.rx_dds_modulo),
    .adc             (adc),
    .sig_i           (rx_i),
    .sig_q           (rx_q)
);

genvar ch;
generate for (ch = 0; ch < N_ADC; ch = ch + 1) begin: gen_rx
    assign sig_i_data[ch] = rx_i[ch];
    assign sig_q_data[ch] = rx_q[ch];
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
// per-drive registers, indexed in the loop generate below
wire [N_DRIVE-1:0] soft_drive_enable = {cfg_dsp.soft_drive1_enable, cfg_dsp.soft_drive0_enable};
wire [N_DRIVE-1:0] drv_pulse_mode = {cfg_dsp.drv1_pulse_mode, cfg_dsp.drv0_pulse_mode};
assign evg_permit_out = soft_drive_enable[0] && sum_drive_enable;  // XXX ALSU specific

// ---------------------
// Triggering logic
// ---------------------
wire wave_trig;
wire int_trig, evr_trig, ext_trig;  // dsp_clk domain
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

wire cbuf_sync;
reg wave_trig_i = 0;
always @(posedge dsp_clk) begin
    case (cfg_dsp.wave_trig_sel)
        WAVE_TRIG_INT:   wave_trig_i <= int_trig;
        WAVE_TRIG_EXT:   wave_trig_i <= ext_trig;
        WAVE_TRIG_SOFT:  wave_trig_i <= cfg_dsp.soft_trigger;
        WAVE_TRIG_EVR:   wave_trig_i <= evr_trig;
        WAVE_TRIG_MIXED: wave_trig_i <= ext_trig | cfg_dsp.soft_trigger;
        default:         wave_trig_i <= cbuf_sync;
    endcase
end

// add trigger delay
pulse_gen #(.AW(24)) trig_delay_gen (
    .clk        (dsp_clk),
    .trigger    (wave_trig_i),
    .start      (cfg_dsp.trigger_delay),
    .high_len   (24'd1),
    .stb_in     (1'b1),
    .res        (4'd0),
    .pulse_dval (wave_trig)
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
    .inlk_permit_mask      (cfg_dsp.inlk_permit_mask),
    .arc_permit_mask       (cfg_dsp.arc_permit_mask),
    .inlk_amp_lo           (inlk_amp_lo),
    .inlk_amp_lo_addr      (inlk_amp_lo_addr),
    .inlk_amp_hi           (inlk_amp_hi),
    .inlk_amp_hi_addr      (inlk_amp_hi_addr),
    .inlk_inlk_mode        (inlk_inlk_mode),
    .inlk_inlk_mode_addr   (inlk_inlk_mode_addr),
    .inlk_reset_inlk       (cfg_dsp.inlk_reset_inlk),
    .arc_reset_latch       (cfg_dsp.arc_reset_latch),
    .arc_reset_arc_dev     (cfg_dsp.arc_reset_arc_dev),
    .arc_test_mask         (cfg_dsp.arc_test_mask),
    .arc_test_stb          (cfg_dsp.arc_test_stb),
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
// Timing module with EVR
// ---------------------
wire [31:0] evr_evcnt_lb;
wire [0:0]  evr_ts_valid_lb;
wire [0:0]  hb_valid_lb;
wire [0:0]  pps_valid_lb;
wire [0:0]  oc_valid_lb;
wire [27:0] oc_evr_frequency;
// XXX should be used for trigger
wire evr_oc_trig_dsp;
wire [63:0] evr_oc_ts_dsp;
timing_core timing_evr (
    .evr_clk             (gt_rxclk),
    .evr_rxd             (gt_rxdata),
    .evr_rxk             (gt_rxcharisk),
    .evcode_evr          (cfg_evr.evcode),
    .event_evr           (),
    .oc_delay_evr        (cfg_evr.evr_oc_delay),

    .sys_clk             (lb_clk),
    .event1_cnt_sys      (evr_evcnt_lb),
    .ts_valid_sys        (evr_ts_valid_lb),
    .live_ts_sys         (),
    .hb_valid_sys        (hb_valid_lb),
    .pps_valid_sys       (pps_valid_lb),
    .oc_valid_sys        (oc_valid_lb),
    .oc_evr_frequency    (oc_evr_frequency),

    .dsp_clk             (dsp_clk),
    .live_ts_dsp         (evr_live_ts_dsp),
    .pps_strobe_dsp      (),
    .hb_strobe_dsp       (),
    .event_dsp           (evr_trig),
    .oc_trig_dsp         (evr_oc_trig_dsp),
    .oc_ts_dsp           (evr_oc_ts_dsp)
);

// ---------------------
// Feedback loops (loop_ctrl replaces them in step 7d)
// ---------------------
// XXX network analyzer setpoints bypassed for now
wire signed [DWBB-1:0] amp_setpoint_ntw;
wire signed [DWBB-1:0] phs_setpoint_ntw;

wire [N_DRIVE-1:0] drive_on;
wire signed [DWBB-1:0] drive_i [0:N_DRIVE-1];
wire signed [DWBB-1:0] drive_q [0:N_DRIVE-1];
bb_t drive_i_out [N_DRIVE];
bb_t drive_q_out [N_DRIVE];
wire signed [DWBB-1:0] amp_measured [0:N_DRIVE-1];
wire signed [DWBB-1:0] phs_measured [0:N_DRIVE-1];
wire signed [DWBB-1:0] amp_setpoint [0:N_DRIVE-1];
wire signed [DWBB-1:0] amp_setpoint_i [0:N_DRIVE-1];
wire signed [DWBB-1:0] max_amp_setpoint [0:N_DRIVE-1];
wire signed [DWBB-1:0] phs_setpoint [0:N_DRIVE-1];
wire [N_DRIVE-1:0] amp_loop_enable;
wire [N_DRIVE-1:0] amp_loop_reset;
wire [N_DRIVE-1:0] phs_loop_enable;
wire [N_DRIVE-1:0] phs_loop_reset;
wire signed [DWBB-1:0] Kp_amp [0:N_DRIVE-1];
wire signed [DWBB-1:0] Kp_phs [0:N_DRIVE-1];
wire signed [DWBB-1:0] Ki_amp [0:N_DRIVE-1];
wire signed [DWBB-1:0] Ki_phs [0:N_DRIVE-1];
wire signed [DWBB-1:0] field_i_data [0:N_DRIVE-1];
wire signed [DWBB-1:0] field_q_data [0:N_DRIVE-1];
wire signed [14:0] err_out_amp [0:N_DRIVE-1];
wire signed [14:0] err_out_phs [0:N_DRIVE-1];
wire signed [14:0] err_out_amp_lb [0:N_DRIVE-1];
wire signed [14:0] err_out_phs_lb [0:N_DRIVE-1];
wire [N_DRIVE-1:0] pulse_dval;
wire [23:0] pulse_start [0:N_DRIVE-1];
wire [23:0] pulse_high_len [0:N_DRIVE-1];

assign pulse_start[0] = cfg_dsp.loop0_pulse_start;
assign pulse_high_len[0] = cfg_dsp.loop0_pulse_high_len;
assign amp_setpoint[0] = cfg_dsp.loop0_amp_setpoint;
assign max_amp_setpoint[0] = cfg_dsp.loop0_max_amp_setpoint;
assign phs_setpoint[0] = cfg_dsp.loop0_phs_setpoint;
assign Kp_amp[0] = cfg_dsp.loop0_Kp_amp;
assign Kp_phs[0] = cfg_dsp.loop0_Kp_phs;
assign Ki_amp[0] = cfg_dsp.loop0_Ki_amp;
assign Ki_phs[0] = cfg_dsp.loop0_Ki_phs;
assign amp_loop_enable[0] = cfg_dsp.loop0_amp_enable;
assign phs_loop_enable[0] = cfg_dsp.loop0_phs_enable;
assign amp_loop_reset[0] = cfg_dsp.loop0_amp_reset;
assign phs_loop_reset[0] = cfg_dsp.loop0_phs_reset;

assign pulse_start[1] = cfg_dsp.loop1_pulse_start;
assign pulse_high_len[1] = cfg_dsp.loop1_pulse_high_len;
assign amp_setpoint[1] = cfg_dsp.loop1_amp_setpoint;
assign max_amp_setpoint[1] = cfg_dsp.loop1_max_amp_setpoint;
assign phs_setpoint[1] = cfg_dsp.loop1_phs_setpoint;
assign Kp_amp[1] = cfg_dsp.loop1_Kp_amp;
assign Kp_phs[1] = cfg_dsp.loop1_Kp_phs;
assign Ki_amp[1] = cfg_dsp.loop1_Ki_amp;
assign Ki_phs[1] = cfg_dsp.loop1_Ki_phs;
assign amp_loop_enable[1] = cfg_dsp.loop1_amp_enable;
assign phs_loop_enable[1] = cfg_dsp.loop1_phs_enable;
assign amp_loop_reset[1] = cfg_dsp.loop1_amp_reset;
assign phs_loop_reset[1] = cfg_dsp.loop1_phs_reset;

assign field_i_data[0] = sig_i_data[cfg_dsp.loop0_adc_chan];
assign field_q_data[0] = sig_q_data[cfg_dsp.loop0_adc_chan];
assign field_i_data[1] = sig_i_data[cfg_dsp.loop1_adc_chan];
assign field_q_data[1] = sig_q_data[cfg_dsp.loop1_adc_chan];

generate for (ch = 0; ch < N_DRIVE; ch = ch + 1) begin: gen_loops
    // in open-loop:   apply max limit to amp_setpoint to avoid DAC saturation.
    // in closed-loop: the amp_setpoint is compared with ADC measurement, so no limit is applied.
    assign amp_setpoint_i[ch] = amp_loop_enable[ch] ? amp_setpoint[ch] :
                                    (amp_setpoint[ch] > max_amp_setpoint[ch] ? max_amp_setpoint[ch] : amp_setpoint[ch]);
    dsp_core #(.KW(DWBB)) feedback (
        .clk              (dsp_clk),
        .reset            (dsp_reset),
        .field_i          (field_i_data[ch]),
        .field_q          (field_q_data[ch]),
        .drive_i          (drive_i[ch]),
        .drive_q          (drive_q[ch]),
        .rx_phase_offset  (cfg_dsp.rx_phase_offset),
        .tx_phase_offset  (cfg_dsp.tx_phase_offset),
        .amp_measured     (amp_measured[ch]),
        .phs_measured     (phs_measured[ch]),
        .amp_setpoint     (amp_setpoint_i[ch]),
        .phs_setpoint     (phs_setpoint[ch]),
        .Kp_amp           (Kp_amp[ch]),
        .Kp_phs           (Kp_phs[ch]),
        .Ki_amp           (Ki_amp[ch]),
        .Ki_phs           (Ki_phs[ch]),
        .amp_loop_enable  (amp_loop_enable[ch]),
        .phs_loop_enable  (phs_loop_enable[ch]),
        .amp_loop_reset   (amp_loop_reset[ch]),
        .phs_loop_reset   (phs_loop_reset[ch]),
        .err_out_amp      (err_out_amp[ch]),
        .err_out_phs      (err_out_phs[ch])
    );

    data_xdomain #(.size(30)) loop_err_xdomain (
        .clk_in   (dsp_clk),
        .gate_in  (dsp_tick),
        .data_in  ({err_out_amp[ch], err_out_phs[ch]}),
        .clk_out  (lb_clk),
        .data_out ({err_out_amp_lb[ch], err_out_phs_lb[ch]})
    );

    // pulsing and permit at baseband
    pulse_gen #(.AW(24)) pulse_gen (
        .clk        (dsp_clk),
        .start      (pulse_start[ch]),
        .trigger    (wave_trig),
        .high_len   (pulse_high_len[ch]),   // unit: DSP_CLK_CYCLE
        .stb_in     (1'b1),
        .res        (4'd0),
        .pulse_dval (pulse_dval[ch])
    );

    assign drive_on[ch] = soft_drive_enable[ch] && sum_drive_enable &&
                          (drv_pulse_mode[ch] ? pulse_dval[ch] : 1'b1);
    assign drive_i_out[ch] = drive_on[ch] ? drive_i[ch] : {DWBB{1'b0}};
    assign drive_q_out[ch] = drive_on[ch] ? drive_q[ch] : {DWBB{1'b0}};

    // base-band loop output for IQ waveform monitoring
    assign sig_i_data[N_ADC+ch] = drive_i_out[ch];
    assign sig_q_data[N_ADC+ch] = drive_q_out[ch];
end endgenerate

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
    .amp_setpoint     (cfg_dsp.loop0_amp_setpoint),
    .phs_setpoint     (cfg_dsp.loop0_phs_setpoint),
    .ntw_phase_debug  (ntw_phase_debug),
    .ntw_cos_debug    (ntw_cos_debug),
    .amp_stp_ntw      (amp_setpoint_ntw), // final amplitude setpoint after excitation
    .phs_stp_ntw      (phs_setpoint_ntw),
    .lo_amp           (cfg_dsp.ntw_lo_amp),
    .modulo           (cfg_dsp.ntw_modulo),
    .phase_step_h     (cfg_dsp.ntw_phase_step_h),
    .phase_step_l     (cfg_dsp.ntw_phase_step_l)
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
assign status_lb.evr_hb_valid = hb_valid_lb;
assign status_lb.evr_pps_valid = pps_valid_lb;
assign status_lb.evr_oc_valid = oc_valid_lb;
assign status_lb.evr_oc_frequency = oc_evr_frequency;
assign status_lb.arc_testing = arc_testing_lb;

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
