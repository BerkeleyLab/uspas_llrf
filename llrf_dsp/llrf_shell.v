`define LB_DECODE_llrf_shell
`include "llrf_shell_auto.vh"

// 18-bit (0 to 3ffff) address map
// write:
//      0 to 0fff   LLRF controller
// read:
//      0 to 0fff   LLRF controller
// 10800            llrf_circle_ready
// 10801            adc_raw_ready
// 10802            sig_iq_buf_ready
// 10911 to 109ff   Slow readout, see slow_bridge.v
// 10a00 to 10a07   amp out
// 10a10 to 10a17   phs out
// 11000 to 117ff   mirror (`define MIRROR_WIDTH 7)
// 12000 to 12fff   adc0_buf
// ...
// 19000 to 19fff   adc7_buf
// 1c000 to 1cfff   adc0_i_buf
// ...
// 23000 to 23fff   adc7_i_buf
// 24000 to 24fff   dac0_i_buf
// 25000 to 25fff   dac1_i_buf
// 26000 to 26fff   adc0_q_buf
// ...
// 2d000 to 2dfff   adc7_q_buf
// 2e000 to 2efff   dac0_q_buf
// 2f000 to 2ffff   dac1_q_buf
// 30000 to 3ffff   Circular buffer

module llrf_shell #(
    parameter integer CBUF_DW = 24,
    parameter integer CBUF_AW = 16,
    parameter integer SIG_BUF_AW = 12,
    localparam integer CIC_SHIFT_BASE = 7,
    localparam integer INLK_SHIFT_BASE = 12, // near 2*np.log2(CIC_BASE_PERIOD) + 3
    localparam integer MON_RW = 44, // must <= 44, see ccfilt.v:51
    localparam integer LB_DW = 32,
    localparam integer LB_ADW = 18,
    localparam integer DW = 16,
    localparam integer DWLO = 18,
    localparam integer DWBB = 18, // base band DW
    localparam integer N_CH = 10,  // N_ADC + N_DAC
    localparam integer N_ADC = 8,
    localparam integer N_DAC = 2
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
    input                dac_clk,
    output reg [DW-1:0]  dac_data_a_out,
    output reg [DW-1:0]  dac_data_b_out,

    // ---------------------
    // Interlock interface
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

    output               trig_out,
    // ---------------------
    // GT transceiver interface
    // ---------------------
    input                gt_rxclk,
    input [15:0]         gt_rxdata,
    input [1:0]          gt_rxcharisk,

    // ---------------------
    // External trigger interface
    // ---------------------
    // XXX simplify
    input [15:0]         etrig_pulse_cnt,
    input                etrig_pulse,
    input                etrig_pulse_delay
);

wire [31:0] lb_data = lb_wdata; // for newad.py

// reg [0:0] circle_buf_flip; top-level single-cycle
// reg [0:0] sig_buf_flip; top-level single-cycle
// newad-force lb1 domain
// reg [7:0] dsp_tag; top-level
// reg [15:0] cbuf_post_delay; top-level
// reg [6:0] wave_samp_per; top-level
// reg [9:0] chan_keep; top-level
// reg [6:0] cic_base_period; top-level
// reg [3:0] cic_wave_shift; top-level
// reg [3:0] inlk_wave_shift; top-level
// reg [9:0] inlk_permit_mask; top-level
// reg [7:0] arc_permit_mask; top-level
// reg [31:0] rx_dds_phase_step; top-level
// reg signed [18:0] rx_dds_phase_shift; top-level
// reg [11:0] rx_dds_modulo; top-level
// reg [17:0] rx_dds_amplitude; top-level
// reg signed [18:0] rx_phase_offset; top-level
// reg signed [18:0] tx_phase_offset; top-level
// reg [2:0] prl_adc_chan; top-level
// reg [2:0] loop0_adc_chan; top-level
// reg [2:0] loop1_adc_chan; top-level
// reg signed [17:0] loop0_amp_setpoint; top-level
// reg signed [17:0] loop0_phs_setpoint; top-level
// reg signed [17:0] loop0_Kp_amp; top-level
// reg signed [17:0] loop0_Kp_phs; top-level
// reg signed [17:0] loop0_Ki_amp; top-level
// reg signed [17:0] loop0_Ki_phs; top-level
// reg [0:0] loop0_amp_enable; top-level
// reg [0:0] loop0_phs_enable; top-level
// reg [0:0] loop0_amp_reset; top-level
// reg [0:0] loop0_phs_reset; top-level
// reg signed [17:0] loop1_amp_setpoint; top-level
// reg signed [17:0] loop1_phs_setpoint; top-level
// reg signed [17:0] loop1_Kp_amp; top-level
// reg signed [17:0] loop1_Kp_phs; top-level
// reg signed [17:0] loop1_Ki_amp; top-level
// reg signed [17:0] loop1_Ki_phs; top-level
// reg [0:0] loop1_amp_enable; top-level
// reg [0:0] loop1_phs_enable; top-level
// reg [0:0] loop1_amp_reset; top-level
// reg [0:0] loop1_phs_reset; top-level
// reg [0:0] dsp_reset; top-level single-cycle
// reg [17:0] loop0_pulse_start; top-level
// reg [17:0] loop0_pulse_high_len; top-level
// reg [17:0] loop1_pulse_start; top-level
// reg [17:0] loop1_pulse_high_len; top-level
// reg [1:0] pulse_modes; top-level
// reg [1:0] dac_permits; top-level
// reg [0:0] ntw_amp_enable; top-level
// reg [0:0] ntw_phs_enable; top-level
// reg [0:0] system_bist_pass; top-level
// reg [1:0] wave_trig_sel; top-level
// reg [0:0] slow_snap_cic; top-level
// newad-force lb2 domain
// reg [1:0] dac_drive_sel; top-level
// reg [31:0] tx_dds_phase_step; top-level
// reg signed [18:0] tx_dds_phase_shift; top-level
// reg [11:0] tx_dds_modulo; top-level
// reg [17:0] tx_dds_amplitude; top-level
// reg [0:0] duc_spectral_flip; top-level
// newad-force lb3 domain
// reg [7:0] evcode; top-level
// reg [6:0] evr_oc_delay; top-level
// newad-force lb domain

// Transfer local bus to dsp clk domain: lb1
wire lb1_clk = dsp_clk;
wire [LB_DW-1:0] lb1_data;
wire [LB_ADW-1:0] lb1_addr;
wire lb1_write;
data_xdomain #(.size(LB_ADW+LB_DW)) lb_to_1x(
    .clk_in(lb_clk), .gate_in(lb_write), .data_in({lb_addr,lb_data}),
    .clk_out(lb1_clk), .gate_out(lb1_write), .data_out({lb1_addr,lb1_data})
);

// Transfer local bus to dac clk domain: lb2
wire lb2_clk = dac_clk;
wire [LB_DW-1:0] lb2_data;
wire [LB_ADW-1:0] lb2_addr;
wire lb2_write;
data_xdomain #(.size(LB_ADW+LB_DW)) lb_to_2x(
    .clk_in(lb_clk), .gate_in(lb_write), .data_in({lb_addr,lb_data}),
    .clk_out(lb2_clk), .gate_out(lb2_write), .data_out({lb2_addr,lb2_data})
);

// Transfer local bus to gt_rxclk domain: lb3
wire lb3_clk = gt_rxclk;
wire [LB_DW-1:0] lb3_data;
wire [LB_ADW-1:0] lb3_addr;
wire lb3_write;
data_xdomain #(.size(LB_ADW+LB_DW)) lb_to_3x(
    .clk_in(lb_clk), .gate_in(lb_write), .data_in({lb_addr,lb_data}),
    .clk_out(lb3_clk), .gate_out(lb3_write), .data_out({lb3_addr,lb3_data})
);

`AUTOMATIC_decode

    // RX NCO LO
    wire signed [DWLO-1:0] cosd, sind;
    dds #( .DWLO(DWLO) ) rx_dds (
        .clk          (dsp_clk),
        .reset        (dsp_reset),
        .amplitude    (rx_dds_amplitude),
        .phase_shift  (rx_dds_phase_shift),
        .phase_step_h (rx_dds_phase_step[31:12]),
        .phase_step_l (rx_dds_phase_step[11:0]),
        .modulo       (rx_dds_modulo),
        .cos_out      (cosd),
        .sin_out      (sind)
    );

    wire wave_trig;
    // signal buffers:
    //    8 ADC for adc_raw_data
    wire signed [DW-1:0] adc_raw_data [0:N_ADC-1];
    wire signed [DW-1:0] adc_raw_out [0:N_ADC-1];
    wire signed [31:0] adc_raw_counts [0:N_ADC-1];
    wire [N_ADC-1:0] adc_raw_ready;

    wire signed [31:0] sig_iq_buf_counts [0:2*N_CH-1];
    wire [2*N_CH-1:0] sig_iq_buf_ready;
    wire [N_CH-1:0] sig_buf_transferred;

    //    2 DAC + 8 ADC for sig_iq_data in base band
    wire [2*N_CH-1:0] sig_buf_iq_transferred;
    wire signed [DWBB-1:0] sig_i_buf_out [0:N_CH-1];
    wire signed [DWBB-1:0] sig_q_buf_out [0:N_CH-1];

    wire [2*N_CH*DWBB-1:0] sig_iq_flat;             // for cic_wave_recorder
    wire signed [DWBB-1:0] sig_i_data [0:N_CH-1];
    wire signed [DWBB-1:0] sig_q_data [0:N_CH-1];

    // synchronize I/Q divider state for multiple DDC channels
    reg i_sel = 0;
    always @(posedge dsp_clk) i_sel <= dsp_reset ? 0 : ~i_sel;

    // create data stream strobes for sig_buf
    // applies to all raw, i, q waveforms
    wire sig_buf_trig = wave_trig;
    reg [SIG_BUF_AW-1:0] sig_buf_cnt=0;
    reg sig_buf_dval=0;
    wire sig_buf_last = &sig_buf_cnt;
    always @(posedge dsp_clk) begin
        if (sig_buf_last) sig_buf_dval <= 0;
        else if (sig_buf_trig) sig_buf_dval <= 1'b1;
        sig_buf_cnt <= sig_buf_dval ? sig_buf_cnt + 1'b1 : 0;
    end

    genvar ch;
    generate for (ch=0; ch<N_ADC; ch=ch+1) begin: gen_adc_raw
        assign adc_raw_data[ch] = adc_data_in[(DW*ch)+:DW];

        ddc #(.DWI(DW), .DWO(DWBB), .DWLO(DWLO)) ddc (
            .clk            (dsp_clk),
            .reset          (dsp_reset),
            .adc            (adc_raw_data[ch]),
            .cosa           (cosd),
            .sina           (sind),
            .i_sel          (i_sel),
            .i_out          (sig_i_data[ch]),
            .q_out          (sig_q_data[ch])
        );

        sig_buf #(.AW(SIG_BUF_AW), .DW(DW)) sig_buf_raw (
            .sig_clk        (dsp_clk                ),
            .sig_dat        (adc_raw_data[ch]       ),
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
    end endgenerate

    generate for (ch=0; ch<N_CH; ch=ch+1) begin: gen_sig_iq
        assign sig_iq_flat[DWBB*(2*ch+0) +:DWBB] = sig_i_data[ch];
        assign sig_iq_flat[DWBB*(2*ch+1) +:DWBB] = sig_q_data[ch];

        sig_buf #(.AW(SIG_BUF_AW), .DW(DWBB)) sig_i_buf (
            .sig_clk        (dsp_clk                ),
            .sig_dat        (sig_i_data[ch]         ),
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
            .sig_clk        (dsp_clk                 ),
            .sig_dat        (sig_q_data[ch]          ),
            .sig_val        (sig_buf_dval            ),
            .sig_last       (sig_buf_last            ),
            .lb_clk         (lb_clk                  ),
            .lb_flip_buf    (sig_buf_flip            ),
            .lb_addr        (lb_addr[SIG_BUF_AW-1:0] ),
            .lb_rdata       (sig_q_buf_out[ch]       ),
            .buf_ready      (sig_iq_buf_ready[10+ch] ),
            .buf_count      (sig_iq_buf_counts[10+ch]),
            .buf_transferred(sig_buf_iq_transferred[10+ch])
        );
    end endgenerate

    wire evr_trig;

    // -- Waveform triggering logic
    localparam WAVE_TRIG_ALWAYS = 0,  // internal trigger
               WAVE_TRIG_EXT    = 1,
               WAVE_TRIG_EXT_DLY= 2,  // XXX remove
               WAVE_TRIG_EVR    = 3;

    // ---------------------
    // Instantiate CBUF
    // ---------------------
    wire [CBUF_DW-1:0] cbuf_out;
    wire cbuf_ready;
    wire cbuf_transferred;
    wire cbuf_sync;

    assign wave_trig = wave_trig_sel==WAVE_TRIG_EXT     ? etrig_pulse :
                       wave_trig_sel==WAVE_TRIG_EXT_DLY ? etrig_pulse_delay :
                       wave_trig_sel==WAVE_TRIG_EVR     ? evr_trig :
                       cbuf_sync; // WAVE_TRIG_ALWAYS
    assign trig_out = wave_trig;

    wire signed [15:0] inlk_data;
    wire inlk_dval, inlk_last;

    // -- slow_snap logic
    wire slow_snap = slow_snap_cic ? cbuf_transferred : sig_buf_iq_transferred[0];

    wire [15:0] slow_rdata;
    wire [63:0] evr_live_ts_dsp;
    wire slow_ready;
    wire inlk_permit_in = drive_permit_in & slow_permit_in;
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
        .evr_timestamp      (evr_live_ts_dsp),
        .cic_wave_samp_per  (wave_samp_per),

        .cic_chan_keep      (chan_keep),
        .cic_base_period    (cic_base_period),
        .cic_wave_shift     (cic_wave_shift),
        .inlk_wave_shift    (inlk_wave_shift),
        .cbuf_post_delay    (cbuf_post_delay),
        .dsp_tag            (dsp_tag),

        .wave_trig          (wave_trig),
        .inlk_permit_in     (inlk_permit_in),
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

    wire mon_valid_out;
    wire [3:0] mon_addr_out;
    wire [15:0] mon_amp_out;
    wire [16:0] mon_phs_out;
    wire [N_CH-1:0] inlk_status;
    wire [N_CH-1:0] inlk_latch;
    wire [N_CH-1:0] inlk_hi;
    wire [N_CH-1:0] inlk_lo;
    wire inlk_permit_out;

    wire fault_valid_out;
    wire [3:0] fault_addr_out;
    wire [15:0] fault_amp_out;
    wire [16:0] fault_phs_out;
    monitor_inlk #(.N_CH(N_CH)) inlk // auto lb1
       (.clk            (dsp_clk),
       .mon_data        (inlk_data),
       .mon_valid       (inlk_dval),
       .mon_last        (inlk_last),
       .mon_amp_out     (mon_amp_out),
       .mon_phs_out     (mon_phs_out),
       .mon_valid_out   (mon_valid_out),
       .mon_addr_out    (mon_addr_out),
       .fault_valid_out (fault_valid_out),
       .fault_addr_out  (fault_addr_out),
       .fault_amp_out   (fault_amp_out),
       .fault_phs_out   (fault_phs_out),
       .cmp_status_hi   (inlk_hi),
       .cmp_status_lo   (inlk_lo),
       .inlk_status     (inlk_status),
       .inlk_latch      (inlk_latch),
       .inlk_permit_in  (inlk_permit_in),
       .inlk_permit_out (inlk_permit_out),
       `AUTOMATIC_inlk);

    wire [2:0] arc_permit_raw;
    wire [2:0] arc_permit_latch;
    wire arc_permit_sum;
    arc_inlk #(.N_CH(3)) arc // auto lb1
        (.clk               (dsp_clk),
        .dev_permit_in      (arc_permit_in),
        .dev_test_out       (arc_test_out),
        .dev_reset_out      (arc_reset_out),
        .permit_raw_out     (arc_permit_raw),
        .permit_latch_out   (arc_permit_latch),
        .permit_sum_out     (arc_permit_sum),
        `AUTOMATIC_arc);

    wire [15:0] mon_amp_lb;
    wire [16:0] mon_phs_lb;
    dpram #(.aw(4),.dw(16+17)) dp_llrf_amp_mon(
        .clka   (dsp_clk),
        .addra  (mon_addr_out),
        .dina   ({mon_amp_out, mon_phs_out}),
        .wena   (mon_valid_out),
        .clkb   (lb_clk),
        .addrb  (lb_addr[3:0]),
        .doutb  ({mon_amp_lb, mon_phs_lb})
    );

    reg [1:0] llrf_circle_ready=0;
    always @(posedge lb_clk) llrf_circle_ready <= {slow_ready, cbuf_ready};

    // Periodically pass the result to lb_clk domain
    reg [2:0] xcnt=0;
    wire dsp_tick = &xcnt;
    always @(posedge dsp_clk) xcnt <= xcnt + 1'b1;

    // ----------------------
    // Feedback controller and TX path
    // ----------------------
    // XXX bypassed for now
    wire signed [DWBB-1:0] amp_setpoint_ntw;
    wire signed [DWBB-1:0] phs_setpoint_ntw;
    // wire signed [DWBB-1:0] phs_setpoint_i = (ntw_phs_enable && loop0_phs_enable) ? phs_setpoint_ntw : loop0_phs_setpoint;
    // wire signed [DWBB-1:0] amp_setpoint_i = (ntw_amp_enable && loop0_amp_enable) ? amp_setpoint_ntw : loop0_amp_setpoint;

    wire tx_dds_reset;
    flag_xdomain dsp_reset_dac (
        .clk1           (dsp_clk),
        .flagin_clk1    (dsp_reset),
        .clk2           (dac_clk),
        .flagout_clk2   (tx_dds_reset)
    );

    wire signed [DWLO-1:0] duc_cos, duc_sin;
    dds #( .DWLO(DWLO) ) tx_dds (
        .clk          (dac_clk),
        .reset        (tx_dds_reset),
        .amplitude    (tx_dds_amplitude),
        .phase_shift  (tx_dds_phase_shift),
        .phase_step_h (tx_dds_phase_step[31:12]),
        .phase_step_l (tx_dds_phase_step[11:0]),
        .modulo       (tx_dds_modulo),
        .cos_out      (duc_cos),
        .sin_out      (duc_sin)
    );

    // mapping
    wire [N_DAC-1:0] drive_on;
    wire signed [DWBB-1:0] drive_i [0:N_DAC-1];
    wire signed [DWBB-1:0] drive_q [0:N_DAC-1];
    wire signed [DWBB-1:0] drive_i_out [0:N_DAC-1];
    wire signed [DWBB-1:0] drive_q_out [0:N_DAC-1];
    wire signed [DWBB-1:0] amp_measured [0:N_DAC-1];
    wire signed [DWBB-1:0] phs_measured [0:N_DAC-1];
    wire signed [DWBB-1:0] amp_setpoint [0:N_DAC-1];
    wire signed [DWBB-1:0] phs_setpoint [0:N_DAC-1];
    wire [N_DAC-1:0] amp_loop_enable;
    wire [N_DAC-1:0] amp_loop_reset;
    wire [N_DAC-1:0] phs_loop_enable;
    wire [N_DAC-1:0] phs_loop_reset;
    wire signed [DWBB-1:0] Kp_amp [0:N_DAC-1];
    wire signed [DWBB-1:0] Kp_phs [0:N_DAC-1];
    wire signed [DWBB-1:0] Ki_amp [0:N_DAC-1];
    wire signed [DWBB-1:0] Ki_phs [0:N_DAC-1];

    wire signed [DWBB-1:0] field_i_data [0:N_DAC-1];
    wire signed [DWBB-1:0] field_q_data [0:N_DAC-1];
    wire signed [DW-1:0] dac_i_out [0:N_DAC-1];
    wire signed [DW-1:0] dac_q_out [0:N_DAC-1];
    wire signed [14:0] err_out_amp [0:N_DAC-1];
    wire signed [14:0] err_out_phs [0:N_DAC-1];
    wire signed [14:0] err_out_amp_lb [0:N_DAC-1];
    wire signed [14:0] err_out_phs_lb [0:N_DAC-1];
    wire [N_DAC-1:0] pulse_val;
    wire [17:0] pulse_start [0:N_DAC-1];
    wire [17:0] pulse_high_len [0:N_DAC-1];

    assign pulse_start[0] = loop0_pulse_start;
    assign pulse_high_len[0] = loop0_pulse_high_len;
    assign amp_setpoint[0] = loop0_amp_setpoint;
    assign phs_setpoint[0] = loop0_phs_setpoint;
    assign Kp_amp[0] = loop0_Kp_amp;
    assign Kp_phs[0] = loop0_Kp_phs;
    assign Ki_amp[0] = loop0_Ki_amp;
    assign Ki_phs[0] = loop0_Ki_phs;
    assign amp_loop_enable[0] = loop0_amp_enable;
    assign phs_loop_enable[0] = loop0_phs_enable;
    assign amp_loop_reset[0] = loop0_amp_reset;
    assign phs_loop_reset[0] = loop0_phs_reset;

    assign pulse_start[1] = loop1_pulse_start;
    assign pulse_high_len[1] = loop1_pulse_high_len;
    assign amp_setpoint[1] = loop1_amp_setpoint;
    assign phs_setpoint[1] = loop1_phs_setpoint;
    assign Kp_amp[1] = loop1_Kp_amp;
    assign Kp_phs[1] = loop1_Kp_phs;
    assign Ki_amp[1] = loop1_Ki_amp;
    assign Ki_phs[1] = loop1_Ki_phs;
    assign amp_loop_enable[1] = loop1_amp_enable;
    assign phs_loop_enable[1] = loop1_phs_enable;
    assign amp_loop_reset[1] = loop1_amp_reset;
    assign phs_loop_reset[1] = loop1_phs_reset;

    assign field_i_data[0] = sig_i_data[loop0_adc_chan];
    assign field_q_data[0] = sig_q_data[loop0_adc_chan];
    assign field_i_data[1] = sig_i_data[loop1_adc_chan];
    assign field_q_data[1] = sig_q_data[loop1_adc_chan];

    generate for (ch=0; ch<N_DAC; ch=ch+1) begin: gen_loops
        // ---------------------
        // feedback controller in baseband
        // ---------------------
        dsp_core #(.KW(DWBB)) feedback (
            .clk              (dsp_clk),
            .reset            (dsp_reset),
            .field_i          (field_i_data[ch]),
            .field_q          (field_q_data[ch]),
            .drive_i          (drive_i[ch]),
            .drive_q          (drive_q[ch]),
            .rx_phase_offset  (rx_phase_offset),
            .tx_phase_offset  (tx_phase_offset),
            .amp_measured     (amp_measured[ch]),
            .phs_measured     (phs_measured[ch]),
            .amp_setpoint     (amp_setpoint[ch]),
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

        // ----------------------
        // Pulsing and permit at baseband
        // ----------------------
        pulse_gen #(.AW(18)) pulse_gen (
            .clk        (dsp_clk),
            .start      (pulse_start[ch]),
            .trigger    (cbuf_sync),        // sync with waveform
            .high_len   (pulse_high_len[ch]),   // unit: DSP_CLK_CYCLE
            .pulse_out  (pulse_val[ch])
        );

        assign drive_on[ch] = dac_permits[ch] && inlk_permit_out && arc_permit_sum && (pulse_modes[ch] ? pulse_val[ch] : 1'b1);
        assign drive_i_out[ch] = drive_on[ch] ? drive_i[ch] : {DWBB{1'b0}};
        assign drive_q_out[ch] = drive_on[ch] ? drive_q[ch] : {DWBB{1'b0}};

        // base-band LOOP output for IQ waveform monitoring
        assign sig_i_data[N_ADC+ch] = drive_i_out[ch];
        assign sig_q_data[N_ADC+ch] = drive_q_out[ch];

        // ----------------------
        // Digital Up Conversion after interpolation and domain crossing to dac_clk
        // ----------------------
        dac_duc #(
            .DWI    (DWBB),
            .DWO    (DW),
            .DWLO   (DWLO)
        ) duc (
            .dsp_clk        (dsp_clk),
            .dsp_reset      (dsp_reset),
            .spectral_flip  (duc_spectral_flip),
            .i_data_in      (drive_i_out[ch]),
            .i_data_valid   (1'b1),
            .q_data_in      (drive_q_out[ch]),
            .q_data_valid   (1'b1),
            .dac_clk        (dac_clk),
            .cosa           (duc_cos),
            .sina           (duc_sin),
            .dac_i_out      (dac_i_out[ch]),
            .dac_q_out      (dac_q_out[ch])
        );
    end endgenerate

    always @(dac_clk) begin
        case (dac_drive_sel)
            2'b00: begin    // loop 0 drives, I0Q0
                dac_data_a_out <= dac_i_out[0];
                dac_data_b_out <= dac_q_out[0];
            end
            2'b01: begin    // loop 1 drives, I1Q1
                dac_data_a_out <= dac_i_out[1];
                dac_data_b_out <= dac_q_out[1];
            end
            2'b10: begin    // dual loops I drive, I0I1
                dac_data_a_out <= dac_i_out[0];
                dac_data_b_out <= dac_i_out[1];
            end
            2'b11: begin    // dual loops Q drive, Q0Q1
                dac_data_a_out <= dac_q_out[0];
                dac_data_b_out <= dac_q_out[1];
            end
            default: begin
                dac_data_a_out <= dac_i_out[0];
                dac_data_b_out <= dac_q_out[0];
            end
        endcase
    end

    // ----------------------
    // Network analyzer feature
    // ----------------------
    // XXX replace by dds.v
    wire ntw_trig_i = (ntw_amp_enable || ntw_phs_enable) ? cbuf_sync : 0;

    wire signed [17:0] ntw_cos_debug;
    wire signed [18:0] ntw_phase_debug;
    ntw_analyzer #(.KW(DWBB)) ntw // auto lb1
    (
        .clk              (dsp_clk),
        .trig             (ntw_trig_i),
        .ext_amp_enable   (ntw_amp_enable),
        .ext_phs_enable   (ntw_phs_enable),
        .amp_setpoint     (loop0_amp_setpoint),
        .phs_setpoint     (loop0_phs_setpoint),
        .ntw_phase_debug  (ntw_phase_debug),
        .ntw_cos_debug    (ntw_cos_debug),
        .amp_stp_ntw      (amp_setpoint_ntw), // final amplitude setpoint after excitation
        .phs_stp_ntw      (phs_setpoint_ntw),
        `AUTOMATIC_ntw
    );

    // timing module with EVR
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
        .evcode_evr          (evcode),
        .event_evr           (),
        .oc_delay_evr        (evr_oc_delay),

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
    // Scalar register readback
    // ---------------------

    wire [N_CH-1:0] inlk_status_lb;
    wire [N_CH-1:0] inlk_latch_lb;
    wire [N_CH-1:0] inlk_hi_lb;
    wire [N_CH-1:0] inlk_lo_lb;
    wire [0:0] inlk_permit_out_lb;
    data_xdomain #(.size(4*N_CH+1)) inlk_stat_xdomain (
        .clk_in   (dsp_clk),
        .gate_in  (dsp_tick),
        .data_in  ({inlk_permit_out, inlk_latch, inlk_status, inlk_hi, inlk_lo}),
        .clk_out  (lb_clk),
        .data_out ({inlk_permit_out_lb, inlk_latch_lb, inlk_status_lb, inlk_hi_lb, inlk_lo_lb})
    );

    wire [2:0] arc_permit_raw_lb;
    wire [2:0] arc_permit_latch_lb;
    wire [0:0] arc_permit_sum_lb;
    data_xdomain #(.size(3+3+1)) arc_stat_xdomain (
        .clk_in   (dsp_clk),
        .gate_in  (dsp_tick),
        .data_in  ({arc_permit_sum, arc_permit_latch, arc_permit_raw}),
        .clk_out  (lb_clk),
        .data_out ({arc_permit_sum_lb, arc_permit_latch_lb, arc_permit_raw_lb})
    );

    // ---------------------
    // Read-only address space decoding
    // ---------------------
    reg [LB_DW-1:0] lb_rdata_r=0;
    reg [LB_ADW-1:0] lb_addr_d1=0;
    reg [31:0] reg_bank_0=0, reg_bank_1=0, reg_bank_2=0;
    // jit_rad == Just In Time Readout Across Domains
    wire lb_error;
    wire xfer_clk, xfer_strobe, xfer_snap;
    wire [3:0] xfer_addr;
    wire [31:0] lb_reg_bank_2;
    jit_rad_gateway #(.passthrough(0)) xfer_bank_6(
        .lb_clk(lb_clk), .lb_addr(lb_addr[3:0]),
        .lb_strobe(lb_read), .lb_odata(lb_reg_bank_2),
        .lb_prefill(lb_prefill), .lb_error(lb_error),
        .app_clk(dsp_clk), .xfer_clk(xfer_clk), .xfer_strobe(xfer_strobe),
        .xfer_addr(xfer_addr), .xfer_odata(reg_bank_2), .xfer_snap(xfer_snap)
    );

    // Want self-consistent readout of all 64 bits of evr_live_ts_dsp.
    // Depends on evr_live_ts_lo being given the xfer_addr[3:0] == 0 slot.
    // See jit_rad_gateway_demo.v for discussion.
    wire [31:0] evr_live_ts_lo = evr_live_ts_dsp[31:0];
    reg  [31:0] evr_live_ts_hi = 0;
    always @(posedge xfer_clk) if (xfer_snap) evr_live_ts_hi = evr_live_ts_dsp[63:32];
    wire [31:0] sig_buf_count = adc_raw_counts[0];

    // lb_read: Match READ_DELAY=3 in system.v, check timing in simulation
    always @(posedge lb_clk) if (lb_read) begin
        case (lb_addr[3:0])
            4'h1: reg_bank_0 <= inlk_hi_lb;           // alias: inlk_hi
            4'h2: reg_bank_0 <= inlk_lo_lb;           // alias: inlk_lo
            4'h3: reg_bank_0 <= inlk_status_lb;       // alias: inlk_status
            4'h4: reg_bank_0 <= inlk_latch_lb;        // alias: inlk_latch
            4'h5: reg_bank_0 <= inlk_permit_out_lb;   // alias: inlk_permit
            4'h6: reg_bank_0 <= arc_permit_raw_lb;    // alias: arc_permit_raw
            4'h7: reg_bank_0 <= arc_permit_latch_lb;  // alias: arc_permit_latch
            4'h8: reg_bank_0 <= arc_permit_sum_lb;    // alias: arc_permit_sum
            4'h9: reg_bank_0 <= err_out_amp_lb[0];    // alias: loop0_amp_err
            4'ha: reg_bank_0 <= err_out_phs_lb[0];    // alias: loop0_phs_err
            4'hb: reg_bank_0 <= err_out_amp_lb[1];    // alias: loop1_amp_err
            4'hc: reg_bank_0 <= err_out_phs_lb[1];    // alias: loop1_phs_err
            4'hd: reg_bank_0 <= evr_evcnt_lb;         // alias: evr_evcnt
            4'he: reg_bank_0 <= evr_ts_valid_lb;      // alias: evr_ts_valid
            default: reg_bank_0 <= 32'hfaceface;
        endcase
        case (lb_addr[3:0])
            4'h1: reg_bank_1 <= hb_valid_lb;          // alias: evr_hb_valid
            4'h2: reg_bank_1 <= pps_valid_lb;         // alias: evr_pps_valid
            4'h3: reg_bank_1 <= oc_valid_lb;          // alias: evr_oc_valid
            4'h4: reg_bank_1 <= oc_evr_frequency;     // alias: evr_oc_frequency
            default: reg_bank_1 <= 32'hfaceface;
        endcase
    end
    always @(posedge xfer_clk) begin
        case (xfer_addr[3:0])
            // All these signals are in dsp_clk domain
            // (and handled with jit_rad)
            4'h0: reg_bank_2 <= evr_live_ts_lo;
            4'h1: reg_bank_2 <= evr_live_ts_hi;
            4'h2: reg_bank_2 <= amp_setpoint_ntw;
            4'h3: reg_bank_2 <= phs_setpoint_ntw;
            4'h4: reg_bank_2 <= sig_buf_count;
            4'h5: reg_bank_2 <= ntw_cos_debug;
            4'h6: reg_bank_2 <= ntw_phase_debug;
            4'h7: reg_bank_2 <= etrig_pulse_cnt;
            default: reg_bank_2 <= 32'hfaceface;
        endcase
    end
    always @(posedge lb_clk) if (lb_read) begin
        lb_addr_d1 <= lb_addr;
        casez (lb_addr_d1)
            18'h10800: lb_rdata_r <= llrf_circle_ready;
            18'h10801: lb_rdata_r <= adc_raw_ready;
            18'h10802: lb_rdata_r <= sig_iq_buf_ready;
            18'h109??: lb_rdata_r <= slow_rdata;
            18'h10a0?: lb_rdata_r <= mon_amp_lb;
            18'h10a1?: lb_rdata_r <= mon_phs_lb;
            18'h11???: lb_rdata_r <= mirror_out_0;
            18'h12???: lb_rdata_r <= adc_raw_out[0];
            18'h13???: lb_rdata_r <= adc_raw_out[1];
            18'h14???: lb_rdata_r <= adc_raw_out[2];
            18'h15???: lb_rdata_r <= adc_raw_out[3];
            18'h16???: lb_rdata_r <= adc_raw_out[4];
            18'h17???: lb_rdata_r <= adc_raw_out[5];
            18'h18???: lb_rdata_r <= adc_raw_out[6];
            18'h19???: lb_rdata_r <= adc_raw_out[7];
            18'h1c???: lb_rdata_r <= sig_i_buf_out[0];  // adc0_i_buf
            18'h1d???: lb_rdata_r <= sig_i_buf_out[1];
            18'h1e???: lb_rdata_r <= sig_i_buf_out[2];
            18'h1f???: lb_rdata_r <= sig_i_buf_out[3];
            18'h20???: lb_rdata_r <= sig_i_buf_out[4];
            18'h21???: lb_rdata_r <= sig_i_buf_out[5];
            18'h22???: lb_rdata_r <= sig_i_buf_out[6];
            18'h23???: lb_rdata_r <= sig_i_buf_out[7];  // adc7_i_buf
            18'h24???: lb_rdata_r <= sig_i_buf_out[8];  // drv0_i_buf
            18'h25???: lb_rdata_r <= sig_i_buf_out[9];  // drv1_i_buf
            18'h26???: lb_rdata_r <= sig_q_buf_out[0];  // adc0_q_buf
            18'h27???: lb_rdata_r <= sig_q_buf_out[1];
            18'h28???: lb_rdata_r <= sig_q_buf_out[2];
            18'h29???: lb_rdata_r <= sig_q_buf_out[3];
            18'h2a???: lb_rdata_r <= sig_q_buf_out[4];
            18'h2b???: lb_rdata_r <= sig_q_buf_out[5];
            18'h2c???: lb_rdata_r <= sig_q_buf_out[6];
            18'h2d???: lb_rdata_r <= sig_q_buf_out[7];  // adc7_q_buf
            18'h2e???: lb_rdata_r <= sig_q_buf_out[8];  // drv0_q_buf
            18'h2f???: lb_rdata_r <= sig_q_buf_out[9];  // drv1_q_buf
            18'h3????: lb_rdata_r <= cbuf_out;
            18'h008??: lb_rdata_r <= 32'h0;  // LEEP old config ROM compatibility
            18'h???0?: lb_rdata_r <= reg_bank_0;
            18'h???1?: lb_rdata_r <= reg_bank_1;
            18'h???2?: lb_rdata_r <= lb_reg_bank_2;
            default:   lb_rdata_r <= 32'hfaceface;
        endcase
    end

    assign lb_rdata = lb_rdata_r;
    assign fast_permit_out = inlk_permit_out & arc_permit_sum;
    assign hpa_permit_out = fast_permit_out;

endmodule
