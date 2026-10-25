// Diagnostics (plan §2.2): raw and I/Q signal buffers, cic_waves (circular
// buffer, slow readout, interlock stream), the RF power interlock
// (monitor_inlk), the ARC interlock (arc_inlk), and their readback words
// and lb_clk status.
module diag
    import llrf_shell_pkg::*;
#(
    parameter integer F_DSP_HZ = 125_000_000,  // sets the arc_inlk 0.5 s pulse
    parameter integer CBUF_DW = 24,
    parameter integer CBUF_AW = 16,
    parameter integer SIG_BUF_AW = 12,
    parameter integer CIC_SHIFT_BASE = 7,
    parameter integer INLK_SHIFT_BASE = 11,
    parameter integer MON_RW = 44
) (
    input                 dsp_clk,
    input                 dsp_reset,
    input                 dsp_tick,          // periodic status transfer to lb_clk
    input  [DW*N_ADC-1:0] adc_data_in,       // slow readout min/max
    input  adc_t          adc [N_ADC],
    input  bb_t           sig_i [N_CH],      // ADC channels, then drives
    input  bb_t           sig_q [N_CH],
    input                 wave_trig,
    input  [31:0]         buf_delay,         // dsp clocks from wave_trig to both captures
    input                 cbuf_free_run,
    input                 record_en,         // drive enabled: record, first fault detection
    input  [63:0]         evr_timestamp,

    // configuration, dsp_clk domain
    input  [6:0]          wave_samp_per,
    input  [9:0]          chan_keep,
    input  [6:0]          cic_base_period,
    input  [3:0]          cic_wave_shift,
    input  [3:0]          inlk_wave_shift,
    input  [15:0]         cbuf_post_delay,
    input  [7:0]          dsp_tag,
    input                 slow_snap_cic,
    input  [9:0]          inlk_permit_mask,
    input  [7:0]          arc_permit_mask,
    // monitor_inlk thresholds and modes (register tables)
    input  [15:0]         inlk_amp_lo,
    output [3:0]          inlk_amp_lo_addr,
    input  [15:0]         inlk_amp_hi,
    output [3:0]          inlk_amp_hi_addr,
    input  [1:0]          inlk_inlk_mode,
    output [3:0]          inlk_inlk_mode_addr,
    input                 inlk_reset_inlk,
    input                 arc_reset_latch,
    input                 arc_reset_arc_dev,
    input  [7:0]          arc_test_mask,
    input                 arc_test_stb,

    // ARC detectors
    input  [2:0]          arc_permit_in,
    output [2:0]          arc_test_out,
    output                arc_reset_out,

    // dsp_clk outputs
    output                cbuf_sync,
    output [0:0]          inlk_arc_permit,   // RF power and ARC permits
    output [31:0]         sig_buf_count,

    // localbus
    input                 lb_clk,
    input                 lb_read,
    input  [LB_ADW-1:0]   lb_addr,
    input  [LB_ADW-1:0]   lb_addr_d1,        // read address of the data on rd_*
    input                 sig_buf_flip,
    input                 circle_buf_flip,
    output [31:0]         rd_circle_ready,
    output [31:0]         rd_sig_buf_ready,
    output [31:0]         rd_sig_iq_buf_ready,
    output [31:0]         rd_slow,
    output [31:0]         rd_mon_amp,
    output [31:0]         rd_mon_phs,
    output [31:0]         rd_fault_amp,
    output [31:0]         rd_adc_buf [N_ADC],
    output [31:0]         rd_sig_i_buf [N_CH],
    output [31:0]         rd_sig_q_buf [N_CH],
    output [31:0]         rd_cbuf,
    // lb_clk status
    output [N_CH-1:0]     inlk_hi_lb,
    output [N_CH-1:0]     inlk_lo_lb,
    output [N_CH-1:0]     inlk_status_lb,
    output [N_CH-1:0]     first_fault_status_lb,
    output [N_CH-1:0]     inlk_latch_lb,
    output [0:0]          inlk_permit_out_lb,
    output [2:0]          arc_permit_raw_lb,
    output [2:0]          arc_permit_latch_lb,
    output [0:0]          arc_permit_sum_lb,
    output [0:0]          arc_testing_lb
);

// ---------------------
// Signal buffers: raw ADC, and I/Q of the ADC and drive channels
// ---------------------
wire signed [DW-1:0] adc_raw_out [0:N_ADC-1];
wire signed [31:0] adc_raw_counts [0:N_ADC-1];
wire [N_ADC-1:0] adc_raw_ready;
wire [N_ADC-1:0] sig_buf_transferred;

wire signed [31:0] sig_iq_buf_counts [0:2*N_CH-1];
wire [2*N_CH-1:0] sig_iq_buf_ready;
wire [2*N_CH-1:0] sig_buf_iq_transferred;
wire signed [DWBB-1:0] sig_i_buf_out [0:N_CH-1];
wire signed [DWBB-1:0] sig_q_buf_out [0:N_CH-1];
wire [2*N_CH*DWBB-1:0] sig_iq_flat;  // for cic_wave_recorder

// data stream strobes for all raw, I and Q buffers
wire sig_buf_dval, sig_buf_last;
pulse_gen #(.AW(32)) sig_buf_trig_gen (
    .clk        (dsp_clk),
    .trigger    (wave_trig),
    .start      (buf_delay),
    .high_len   (1<<SIG_BUF_AW),
    .stb_in     (1'b1),
    .res        (4'd0),
    .pulse_dval (sig_buf_dval),
    .pulse_last (sig_buf_last)
);

genvar ch;
generate for (ch = 0; ch < N_ADC; ch = ch + 1) begin: gen_adc_raw
    sig_buf #(.AW(SIG_BUF_AW), .DW(DW)) sig_buf_raw (
        .sig_clk        (dsp_clk                ),
        .sig_dat        (adc[ch]                ),
        .sig_val        (sig_buf_dval           ),
        .sig_last       (sig_buf_last           ),
        .lb_clk         (lb_clk                 ),
        .lb_flip_buf    (sig_buf_flip           ),
        .lb_addr        (lb_addr[SIG_BUF_AW-1:0]),
        .lb_rdata       (adc_raw_out[ch]        ),
        .buf_ready      (adc_raw_ready[ch]      ),
        .buf_count      (adc_raw_counts[ch]     ),
        .buf_transferred(sig_buf_transferred[ch])
    );
    assign rd_adc_buf[ch] = {{(32-DW){adc_raw_out[ch][DW-1]}}, adc_raw_out[ch]};
end endgenerate

generate for (ch = 0; ch < N_CH; ch = ch + 1) begin: gen_sig_iq
    assign sig_iq_flat[DWBB*(2*ch+0) +:DWBB] = sig_i[ch];
    assign sig_iq_flat[DWBB*(2*ch+1) +:DWBB] = sig_q[ch];

    sig_buf #(.AW(SIG_BUF_AW), .DW(DWBB)) sig_i_buf (
        .sig_clk        (dsp_clk                ),
        .sig_dat        (sig_i[ch]              ),
        .sig_val        (sig_buf_dval           ),
        .sig_last       (sig_buf_last           ),
        .lb_clk         (lb_clk                 ),
        .lb_flip_buf    (sig_buf_flip           ),
        .lb_addr        (lb_addr[SIG_BUF_AW-1:0]),
        .lb_rdata       (sig_i_buf_out[ch]      ),
        .buf_ready      (sig_iq_buf_ready[ch]   ),
        .buf_count      (sig_iq_buf_counts[ch]  ),
        .buf_transferred(sig_buf_iq_transferred[ch])
    );

    sig_buf #(.AW(SIG_BUF_AW), .DW(DWBB)) sig_q_buf (
        .sig_clk        (dsp_clk                      ),
        .sig_dat        (sig_q[ch]                    ),
        .sig_val        (sig_buf_dval                 ),
        .sig_last       (sig_buf_last                 ),
        .lb_clk         (lb_clk                       ),
        .lb_flip_buf    (sig_buf_flip                 ),
        .lb_addr        (lb_addr[SIG_BUF_AW-1:0]      ),
        .lb_rdata       (sig_q_buf_out[ch]            ),
        .buf_ready      (sig_iq_buf_ready[N_CH+ch]    ),
        .buf_count      (sig_iq_buf_counts[N_CH+ch]   ),
        .buf_transferred(sig_buf_iq_transferred[N_CH+ch])
    );
    assign rd_sig_i_buf[ch] = {{(32-DWBB){sig_i_buf_out[ch][DWBB-1]}}, sig_i_buf_out[ch]};
    assign rd_sig_q_buf[ch] = {{(32-DWBB){sig_q_buf_out[ch][DWBB-1]}}, sig_q_buf_out[ch]};
end endgenerate

assign sig_buf_count = adc_raw_counts[0];
assign rd_sig_buf_ready = {{(32-N_ADC){1'b0}}, adc_raw_ready};
assign rd_sig_iq_buf_ready = {{(32-2*N_CH){1'b0}}, sig_iq_buf_ready};

// ---------------------
// cic_waves: circular buffer, slow readout and interlock stream
// ---------------------
// circle buffer trigger: wave_trig delayed by buf_delay, one clock high
// (same pulse_gen latency as the signal buffer capture above)
wire cbuf_trig;
pulse_gen #(.AW(32)) cbuf_trig_gen (
    .clk        (dsp_clk),
    .trigger    (wave_trig),
    .start      (buf_delay),
    .high_len   (32'd1),
    .stb_in     (1'b1),
    .res        (4'd0),
    .pulse_dval (cbuf_trig)
);

wire [CBUF_DW-1:0] cbuf_out;
wire cbuf_ready;
wire cbuf_transferred;
wire signed [15:0] inlk_data;
wire inlk_dval, inlk_last;

// slow readout snapshot: on cbuf transfer (CW) or I/Q buffer transfer (pulsed)
wire slow_snap = slow_snap_cic ? cbuf_transferred : sig_buf_iq_transferred[0];

wire [15:0] slow_rdata;
wire slow_ready;
cic_waves #(
    .N_CH               (N_CH),
    .N_ADC              (N_ADC),
    .DW                 (DW),
    .DWIQ               (DWBB),
    .MON_RW             (MON_RW),
    .CBUF_AW            (CBUF_AW),
    .CBUF_DW            (CBUF_DW),
    .CIC_SHIFT_BASE     (CIC_SHIFT_BASE),
    .INLK_SHIFT_BASE    (INLK_SHIFT_BASE)
) cic_waves (
    .dsp_clk            (dsp_clk),
    .dsp_reset          (dsp_reset),
    .iq_dval            (1'b1),
    .iq_data            (sig_iq_flat),

    .slow_bridge_data_in(adc_data_in),
    .slow_snap          (slow_snap),
    .evr_timestamp      (evr_timestamp),
    .cic_wave_samp_per  (wave_samp_per),

    .cic_chan_keep      (chan_keep),
    .cic_base_period    (cic_base_period),
    .cic_wave_shift     (cic_wave_shift),
    .inlk_wave_shift    (inlk_wave_shift),
    .cbuf_post_delay    (cbuf_post_delay),
    .dsp_tag            (dsp_tag),

    .wave_trig          (cbuf_trig),
    .cbuf_free_run      (cbuf_free_run),
    .record_en          (record_en),

    .inlk_data          (inlk_data),
    .inlk_dval          (inlk_dval),
    .inlk_last          (inlk_last),

    .lb_clk             (lb_clk),
    .lb_read            (lb_read),
    .lb_addr            (lb_addr),
    .cbuf_sync          (cbuf_sync),
    .cbuf_transferred   (cbuf_transferred),
    .cbuf_buf_flip      (circle_buf_flip),
    .cbuf_ready         (cbuf_ready),
    .cbuf_out           (cbuf_out),
    .slow_ready         (slow_ready),
    .slow_rdata         (slow_rdata)
);
assign rd_cbuf = {{(32-CBUF_DW){1'b0}}, cbuf_out};
assign rd_slow = {16'b0, slow_rdata};

reg [1:0] llrf_circle_ready = 0;
always @(posedge lb_clk) llrf_circle_ready <= {slow_ready, cbuf_ready};
assign rd_circle_ready = {30'b0, llrf_circle_ready};

// ---------------------
// RF power interlock
// ---------------------
wire mon_valid_out;
wire [3:0] mon_addr_out;
wire [15:0] mon_amp_out;
wire [16:0] mon_phs_out;
wire [N_CH-1:0] inlk_status;
wire [N_CH-1:0] first_fault_status;
wire [N_CH-1:0] inlk_latch;
wire [N_CH-1:0] inlk_hi;
wire [N_CH-1:0] inlk_lo;
wire inlk_permit_out;

wire fault_valid_out;
wire [3:0] fault_addr_out;
wire [15:0] fault_amp_out;
wire [16:0] fault_phs_out;
monitor_inlk #(.N_CH(N_CH)) inlk (
    .clk               (dsp_clk),
    .permit_mask       (inlk_permit_mask),
    .mon_data          (inlk_data),
    .mon_valid         (inlk_dval),
    .mon_last          (inlk_last),
    .mon_amp_out       (mon_amp_out),
    .mon_phs_out       (mon_phs_out),
    .mon_valid_out     (mon_valid_out),
    .mon_addr_out      (mon_addr_out),

    .record_status_en  (record_en),  // first fault detection
    .fault_valid_out   (fault_valid_out),
    .fault_addr_out    (fault_addr_out),
    .fault_amp_out     (fault_amp_out),
    .fault_phs_out     (fault_phs_out),

    .cmp_status_hi     (inlk_hi),
    .cmp_status_lo     (inlk_lo),
    .inlk_status       (inlk_status),
    .first_fault_status(first_fault_status),
    .inlk_latch        (inlk_latch),
    .inlk_permit_out   (inlk_permit_out),
    .amp_lo            (inlk_amp_lo),
    .amp_lo_addr       (inlk_amp_lo_addr),
    .amp_hi            (inlk_amp_hi),
    .amp_hi_addr       (inlk_amp_hi_addr),
    .reset_inlk        (inlk_reset_inlk),
    .inlk_mode         (inlk_inlk_mode),
    .inlk_mode_addr    (inlk_inlk_mode_addr)
);

// ---------------------
// ARC interlock
// ---------------------
wire [2:0] arc_permit_raw;
wire [2:0] arc_permit_latch;
wire arc_permit_sum;
wire arc_testing;
arc_inlk #(.N_CH(3), .F_CLK(F_DSP_HZ)) arc (
    .clk              (dsp_clk),
    .permit_mask      (arc_permit_mask),
    .dev_permit_in    (arc_permit_in),
    .dev_test_out     (arc_test_out),
    .dev_reset_out    (arc_reset_out),
    .permit_raw_out   (arc_permit_raw),
    .permit_latch_out (arc_permit_latch),
    .permit_sum_out   (arc_permit_sum),
    .testing_out      (arc_testing),
    .reset_latch      (arc_reset_latch),
    .reset_arc_dev    (arc_reset_arc_dev),
    .test_mask        (arc_test_mask),
    .test_stb         (arc_test_stb)
);

assign inlk_arc_permit = inlk_permit_out & arc_permit_sum;

// ---------------------
// Readback of monitor and fault records, status to lb_clk
// ---------------------
wire [15:0] mon_amp_lb;
wire [16:0] mon_phs_lb;
dpram #(.aw(4), .dw(16+17)) dp_llrf_amp_mon (
    .clka   (dsp_clk),
    .addra  (mon_addr_out),
    .dina   ({mon_amp_out, mon_phs_out}),
    .wena   (mon_valid_out),
    .clkb   (lb_clk),
    .addrb  (lb_addr[3:0]),
    .doutb  ({mon_amp_lb, mon_phs_lb})
);
assign rd_mon_amp = {16'b0, mon_amp_lb};
assign rd_mon_phs = {15'b0, mon_phs_lb};

data_xdomain #(.size(5*N_CH+1)) inlk_stat_xdomain (
    .clk_in   (dsp_clk),
    .gate_in  (dsp_tick),
    .data_in  ({inlk_permit_out, first_fault_status, inlk_latch, inlk_status, inlk_hi, inlk_lo}),
    .clk_out  (lb_clk),
    .data_out ({inlk_permit_out_lb, first_fault_status_lb, inlk_latch_lb, inlk_status_lb, inlk_hi_lb, inlk_lo_lb})
);

// Latch fault record amplitude per channel, addressed by fault_addr_out
reg [16*N_CH-1:0] fault_amp_r = 0;
always @(posedge dsp_clk) if (fault_valid_out && fault_addr_out < N_CH)
    fault_amp_r[16*fault_addr_out +: 16] <= fault_amp_out;

wire [16*N_CH-1:0] fault_amp_xd;
data_xdomain #(.size(16*N_CH)) fault_amp_xdomain (
    .clk_in   (dsp_clk),
    .gate_in  (dsp_tick),
    .data_in  (fault_amp_r),
    .clk_out  (lb_clk),
    .data_out (fault_amp_xd)
);
wire [15:0] fault_amp_lb = lb_addr_d1[3:0] < N_CH ? fault_amp_xd[16*lb_addr_d1[3:0] +: 16] : 16'h0;
assign rd_fault_amp = {16'b0, fault_amp_lb};

data_xdomain #(.size(1+3+3+1)) arc_stat_xdomain (
    .clk_in   (dsp_clk),
    .gate_in  (dsp_tick),
    .data_in  ({arc_testing, arc_permit_sum, arc_permit_latch, arc_permit_raw}),
    .clk_out  (lb_clk),
    .data_out ({arc_testing_lb, arc_permit_sum_lb, arc_permit_latch_lb, arc_permit_raw_lb})
);

endmodule
