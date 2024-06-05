`define LB_DECODE_llrf_shell
`include "settings.vams"
`include "llrf_shell_auto.vh"

// 18-bit (0 to 3ffff) address map
// write:
//      0 to 0fff   LLRF controller
// read:
//      0 to 0fff   LLRF controller
// 08000 to 087ff   Json ROM
// 12011 to 120ff   Slow readout, see slow_bridge.v
// 13000 to 13007   amp out
// 13010 to 13017   phs out
// 20000 to 2ffff   Circular buffer

module llrf_shell #(
    parameter integer CIC_BASE_PERIOD = `CIC_BASE_PERIOD,
    parameter integer SHIFT_BASE = `SHIFT_BASE,
    parameter integer SHIFT_INLK = `SHIFT_INLK,
    parameter integer CBUF_DW = 24,
    parameter integer CBUF_AW = 16,
    parameter integer GIT_REV_ID = 0,
    localparam integer MON_RW = 44, // must <= 44, see ccfilt.v:51
    localparam integer LB_DW = 32,
    localparam integer LB_ADW = 18,
    localparam integer DW = 16,
    localparam integer DWLO = 18,
    localparam integer DAVR = 3, // Guard bits to keep in output of mixer
    localparam integer N_ADC = 8,
    localparam integer N_DAC = 2,
    localparam integer N_CH = 10 // N_ADC + N_DAC
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

    // ---------------------
    // Digitizer interface
    // ---------------------
    input                dsp_clk,
    input [DW*N_ADC-1:0] adc_data_in,
    output [DW-1:0]      dac_data_a_out,
    output [DW-1:0]      dac_data_b_out,

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

    output               trig_out
);


wire [DW-1:0] adc_phy_dat [0:N_ADC-1];
assign adc_phy_dat[0] = adc_data_in[DW*0 +:DW];
assign adc_phy_dat[1] = adc_data_in[DW*1 +:DW];
assign adc_phy_dat[2] = adc_data_in[DW*2 +:DW];
assign adc_phy_dat[3] = adc_data_in[DW*3 +:DW];
assign adc_phy_dat[4] = adc_data_in[DW*4 +:DW];
assign adc_phy_dat[5] = adc_data_in[DW*5 +:DW];
assign adc_phy_dat[6] = adc_data_in[DW*6 +:DW];
assign adc_phy_dat[7] = adc_data_in[DW*7 +:DW];

wire signed [15:0] cav_cel = adc_phy_dat[3];        // for feedback
wire wave_trig;

wire [15:0] adc_buf_out [0:N_ADC-1];
genvar i;
generate for (i=0; i<N_ADC; i=i+1)
    begin: gen_buf_adc
    adc_buf #(.AW(12), .DW(DW)) adc_buf_i (
        .wfm_len        (12'd4095       ),
        .adc_trigger    (wave_trig      ),
        .adc_phy_clk    (dsp_clk        ),
        .adc_phy_dat    (adc_phy_dat[i] ),
        .adc_phy_val    (1'b1),
        .lb_clk         (lb_clk         ),
        .lb_read        (lb_read        ),
        .lb_rvalid      (lb_rvalid      ),
        .lb_addr        (lb_addr[11:0]  ),
        .lb_rdata       (adc_buf_out[i] )
    );
    end
endgenerate

wire [DW-1:0] dac_phy_dat [0:N_DAC-1];
assign dac_phy_dat[0] = dac_data_a_out;
assign dac_phy_dat[1] = dac_data_b_out;
wire [15:0] dac_buf_out [0:N_DAC-1];

genvar j;
generate for (j=0; j<N_DAC; j=j+1)
    begin: gen_buf_dac
    adc_buf #(.AW(12), .DW(DW)) dac_buf_i (
        .wfm_len        (12'd4095       ),
        .adc_trigger    (wave_trig      ),
        .adc_phy_clk    (dsp_clk        ),
        .adc_phy_dat    (dac_phy_dat[j] ),
        .adc_phy_val    (1'b1),
        .lb_clk         (lb_clk         ),
        .lb_read        (lb_read        ),
        .lb_rvalid      (lb_rvalid      ),
        .lb_addr        (lb_addr[11:0]  ),
        .lb_rdata       (dac_buf_out[j] )
    );
    end
endgenerate

wire [DW*N_CH-1:0] dac_adc_flat = {dac_data_b_out, dac_data_a_out, adc_data_in};
wire inlk_permit_in = drive_permit_in & slow_permit_in;

wire [31:0] lb_data = lb_wdata; // for newad.py

// reg [7:0] dsp_tag; top-level
// reg [15:0] cbuf_post_delay; top-level
// reg [6:0] wave_samp_per; top-level
// reg [9:0] chan_keep; top-level
// reg [2:0] wave_shift; top-level
// reg [0:0] circle_buf_flip; top-level single-cycle
// reg [0:0] dds_reset; top-level single-cycle
// reg [31:0] dds_phase_step; top-level
// reg [18:0] dds_phase_shift; top-level
// reg [11:0] dds_modulo; top-level
// reg signed [17:0] amp_setpoint; top-level
// reg signed [17:0] phs_setpoint; top-level
// reg signed [17:0] Kp_amp; top-level
// reg signed [17:0] Kp_phs; top-level
// reg signed [17:0] Ki_amp; top-level
// reg signed [17:0] Ki_phs; top-level
// reg [0:0] amp_loop_enable; top-level
// reg [0:0] phs_loop_enable; top-level
// reg [0:0] amp_loop_reset; top-level
// reg [0:0] phs_loop_reset; top-level
// reg [0:0] dsp_reset; top-level
// reg [31:0] pulse_high_len; top-level
// reg [0:0] pulse_mode; top-level
// reg [0:0] dac_permit; top-level
// reg [0:0] ntw_amp_enable; top-level
// reg [0:0] ntw_phs_enable; top-level
// reg [17:0] ntw_lo_amp; top-level
// reg [31:0] ntw_phase_step_h; top-level
// reg [11:0] ntw_phase_step_l; top-level
// reg [11:0] ntw_modulo; top-level

// Transfer local bus to dsp clk domain:
 wire lb1_clk = dsp_clk;
 wire [LB_DW-1:0] lb1_data;
 wire [LB_ADW-1:0] lb1_addr;
 wire lb1_write;
`AUTOMATIC_decode
 data_xdomain #(.size(LB_ADW+LB_DW)) lb_to_1x(
     .clk_in(lb_clk), .gate_in(lb_write), .data_in({lb_addr,lb_data}),
     .clk_out(lb1_clk), .gate_out(lb1_write), .data_out({lb1_addr,lb1_data})
 );

    wire signed [DWLO-1:0] cosd, sind;
    wire [18:0] dds_phase_acc;
    ph_acc dds_lo (
        .clk            (dsp_clk),
        .reset          (dds_reset),
        .en             (1'b1),
        .phase_acc      (dds_phase_acc),
        .phase_step_h   (dds_phase_step[31:12]),
        .phase_step_l   (dds_phase_step[11: 0]),
        .modulo         (dds_modulo)
    );

    // LO for RX (feedback)
    cordicg_b22 #(.nstg(20), .width(18)) dds_cordicg_i(
        .clk            (dsp_clk),
        .opin           (2'b00),
        .xin            (18'd`LO_AMP),
        .yin            (18'd0),
        .phasein        (dds_phase_acc + dds_phase_shift),
        .xout           (cosd),
        .yout           (sind)
    );

    // LO for waveform
    wire signed [DWLO-1:0] cosdd, sindd;
    // rotate -90 deg to compensate CIC phase gain
    wire [DWLO:0] dds_wf_phase = dds_phase_acc  + dds_phase_shift - 19'd131072;
    cordicg_b22 #(.nstg(20), .width(18)) dds_cordicg_wf(
        .clk            (dsp_clk),
        .opin           (2'b00),
        .xin            (18'd`LO_AMP),
        .yin            (18'd0),
        .phasein        (dds_wf_phase),
        .xout           (cosdd),
        .yout           (sindd)
    );

    wire [2*N_CH*(DW+DAVR)-1:0] iq_in_flat;

    genvar ix;
    generate for (ix=0; ix<N_CH; ix=ix+1) begin: gen_mixer
        // digital down conversion uses LO = exp(-jwt) = cos(jwt) - sin(jwt)
        mixer #(.dwi(DW),.davr(DAVR),.dwlo(DWLO)) mixi(
            .clk    (dsp_clk),
            .adcf   (dac_adc_flat[(DW*ix)+:DW]),
            .mult   (cosdd),
            .mixout (iq_in_flat[(DW+DAVR)*(2*ix+1) +:(DW+DAVR)]));   // real
        mixer #(.dwi(DW),.davr(DAVR),.dwlo(DWLO)) mixq(
            .clk    (dsp_clk),
            .adcf   (dac_adc_flat[(DW*ix)+:DW]),
            .mult   (-sindd),
            .mixout (iq_in_flat[(DW+DAVR)*(2*ix+0) +:(DW+DAVR)]));   // imag
        end
    endgenerate

    // ---------------------
    // Instantiate Sampler
    // ---------------------
    wire cic_sample, cc_sample;

    cic_timing #(
        .CIC_BASE_PERIOD(CIC_BASE_PERIOD)
    ) cic_timing_i (
        .clk            (dsp_clk),
        .wave_samp_per  (wave_samp_per),
        .cic_sample     (cic_sample),
        .sample_wave    (cc_sample)
    );

    // ---------------------
    // Instantiate CBUF
    // ---------------------
    wire [CBUF_DW-1:0] cbuf_out;
    wire llrf_circle_ready;
    wire cbuf_transferred;
    wire cbuf_sync;
    wire [15:0] cbuf_count;
    wire [15:0] cbuf_stat1;
    wire [CBUF_AW-1:0] cbuf_stat2;

    // -- Waveform triggering logic
    // internal trigger only, synchronized with waveform
    assign wave_trig = cbuf_sync;
    assign trig_out = wave_trig;

    reg cbuf_write=1;
    reg cbuf_start=0;
    always @(posedge dsp_clk) begin
        cbuf_start <= 1'b0;
        if (cbuf_sync) cbuf_write <= 1'b0;
        if (wave_trig) begin
            cbuf_write <= 1'b1;
            if (!cbuf_write || cbuf_sync) cbuf_start <= 1'b1;
        end
    end

    // -- Waveform freeze logic
    reg [16:0] delay_cnt=0;
    wire       cbuf_delay_stop = (delay_cnt == cbuf_post_delay);
    reg        cbuf_delay_stop1=0;
    wire cbuf_stop = cbuf_delay_stop & ~cbuf_delay_stop1;
    always @(posedge dsp_clk) begin
        cbuf_delay_stop1 <= cbuf_delay_stop;
        delay_cnt <= inlk_permit_in ? 0 :
        cbuf_delay_stop ? delay_cnt : delay_cnt + cbuf_sync;
    end

    wire        di_stb_out;
    wire [MON_RW-1:0] di_sr_out;
    wire [2*N_CH-1:0] chan_keep_iq;
    gen_chan_keep_iq #(.N_CH(N_CH)) gen_chan_keep_iq_i (
        .chan_keep      (chan_keep[N_CH-1:0]),
        .chan_keep_iq   (chan_keep_iq)
    );

    wire [CBUF_AW-1:0] cbuf_addr = lb_addr[CBUF_AW-1:0];
    cic_wave_recorder #(
        .n_chan        (2*N_CH),
        .di_dwi        (DW+DAVR),  // data width
        .di_rwi        (MON_RW),  // result width
                        // Difference between above two widths should be N*log2 of the maximum number
                        // of samples per CIC sample, where N=2 is the order of the CIC filter.
        .di_noise_bits (0),
        .cc_outw       (CBUF_DW),       // CCFilt output width; Must be 20 if using half-band filter
        .cc_halfband   (0),
        .cc_shift_base (SHIFT_BASE),   // Bits to discard from previous acc step
        .buf_dw        (CBUF_DW),
        .buf_aw        (CBUF_AW),
        .lsb_mask      (1),             // LSB of channel mask is CH0
        .buf_auto_flip (0)
    ) cic_wave_recorder_i (
        .iclk         (dsp_clk),
        .reset        (dsp_reset),
        .stb_in       (1'b1),
        .d_in         (iq_in_flat),   // Flattened array of unprocessed IQ streams. CH0 in LSBs
        .cic_sample   (cic_sample),

        // Post-integrator conveyor belt tap
        .di_stb_out   (di_stb_out),
        .di_sr_out    (di_sr_out),

        .cc_sample    (cc_sample),
        .cc_shift     ({wave_shift, 1'b0}), // controls scaling of filter result

        // Channel selector controls
        .chan_mask    (chan_keep_iq),     // Bitmask of channels to record. chan_mask[0] -> CH0

        // Circular Buffer control and statistics
        .oclk         (lb_clk),
        .buf_write    (cbuf_write),

        .buf_sync     (cbuf_sync),            // single-cycle when buffer starts/ends
        .buf_transferred(cbuf_transferred),    // single-cycle when a buffer has been
        .buf_stop     (cbuf_stop),             // single-cycle - interrupts cbuf writing
        .buf_count    (cbuf_count),
        .buf_stat2    (cbuf_stat2),         // includes fault bit
        .buf_stat     (cbuf_stat1),         // includes fault bit(), and (if set) the last valid location
        .debug_stat   (),            // {stb_in(), boundary(), btest(), wbank(), rbank(), wr_addr}

        // Circular Buffer data readout
        .buf_stb      (circle_buf_flip),
        .buf_enable   (llrf_circle_ready),
        .buf_read_addr(cbuf_addr),
        .buf_d_out    (cbuf_out)
    );

    // ---------------------
    // For interlock stream, fixed dw=16, fixed decimation.
    // ---------------------
    wire signed [15:0] inlk_data;
    wire inlk_dval;
    ccfilt #(
       .dw         (MON_RW),
       .outw       (16),
       .shift_base (SHIFT_INLK),     // 2*np.log2(CIC_BASE_PERIOD) + 3
       .dsr_len    (2*N_CH),
       .use_hb     (0)
    ) inlk_ccfilt (
       .clk      (dsp_clk),
       .reset    (dsp_reset),
       .sr_in    (di_sr_out),
       .sr_valid (di_stb_out),    // fixed wave_samp_per = 1
       .shift    (4'b0),
       .result   (inlk_data),     // signed filtered and scaled result
       .strobe   (inlk_dval)
    );

    reg [8:0] inlk_count=0;
    always @(posedge dsp_clk) inlk_count <= inlk_dval ? inlk_count + 1 : 0;
    wire inlk_last = inlk_count == (2*N_CH-1);

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

    // ---------------------
    // Instantiate diagnostics buffer
    //     synchronized with waveform
    //     for adc_min / adc_max, timestamp, waveform status,
    //     and snap for validation of a waveform if register changed in between
    // ---------------------
    wire slow_ready;
    // wire lb_slow_read = lb_read && (lb_addr[17:8] == 'b1_0010_0000);  // 0x12000 to 0x120ff
    wire [15:0] lb_slow_rdata;
    wire [15:0] cbuf_stat2_pad = cbuf_stat2;
    slow_bridge_shell #(.AW(7), .DW(DW), .N_CH(N_ADC)) slow_bridge_i (
        .lb_clk         (lb_clk),
        .lb_addr        (lb_addr[6:0]),
        .lb_read        (lb_read),
        .lb_rdata       (lb_slow_rdata),
        .tag            (dsp_tag),

        .dsp_clk        (dsp_clk),
        .buf_start      (cbuf_start),
        .buf_sync       (cbuf_sync),
        .buf_stat1      (cbuf_stat1),
        .buf_stat2      (cbuf_stat2_pad),
        .buf_count      (cbuf_count),
        .buf_ready      (llrf_circle_ready),
        .data_in        (adc_data_in),
        .evr_timestamp  (64'h0),

        .slow_snap      (cbuf_transferred),
        .slow_ready     (slow_ready)
    );

    reg [1:0] slow_cbuf_ready=0;
    always @(posedge lb_clk) slow_cbuf_ready <= {slow_ready, llrf_circle_ready};

    wire signed [17:0] amp_setpoint_ntw;
    wire signed [17:0] phs_setpoint_ntw;
    wire signed [14:0] err_out_amp;
    wire signed [14:0] err_out_phs;
    wire signed [17:0] phs_setpoint_i =  (ntw_phs_enable && phs_loop_enable) ? phs_setpoint_ntw : phs_setpoint;
    wire signed [17:0] amp_setpoint_i =  (ntw_amp_enable && amp_loop_enable) ? amp_setpoint_ntw : amp_setpoint;

    // ---------------------
    // Instantiate dsp_core
    // ---------------------
    wire signed [15:0] dac_out;
    wire [18:0] rx_phase_offset = `RX_LO_PHS;
    wire [18:0] tx_phase_offset = `TX_LO_PHS;
    dsp_core #(.KW(18), .EW(15)) dsp (
        .clk              (dsp_clk),
        .reset            (dsp_reset),
        .cav_field        (cav_cel),
        .cosa             (cosd),
        .sina             (sind),
        .rx_phase_offset  (rx_phase_offset),
        .tx_phase_offset  (tx_phase_offset),
        .dac_out          (dac_out),
        .amp_setpoint     (amp_setpoint_i),
        .phs_setpoint     (phs_setpoint_i),
        .Kp_amp           (Kp_amp),
        .Kp_phs           (Kp_phs),
        .Ki_amp           (Ki_amp),
        .Ki_phs           (Ki_phs),
        .amp_loop_enable  (amp_loop_enable),
        .phs_loop_enable  (phs_loop_enable),
        .amp_loop_reset   (amp_loop_reset),
        .phs_loop_reset   (phs_loop_reset),
        .err_out_amp      (err_out_amp),
        .err_out_phs      (err_out_phs)
    );

    // ----------------------
    // Network analyzer feature
    // ----------------------
    wire ntw_trig_i = (ntw_amp_enable || ntw_phs_enable) ? cbuf_sync : 0;

    wire signed [17:0] ntw_cos_debug;
    wire signed [18:0] ntw_phase_debug;
    ntw_analyzer #(.KW(18))
    ntw_analyzer (
        .clk              (dsp_clk),
        .trig             (ntw_trig_i),

        .ext_amp_enable   (ntw_amp_enable),
        .ext_phs_enable   (ntw_phs_enable),
        .amp_setpoint     (amp_setpoint),
        .phs_setpoint     (phs_setpoint),

        .lo_amp           (ntw_lo_amp),
        .modulo           (ntw_modulo),
        .phase_step_l     (ntw_phase_step_l),
        .phase_step_h     (ntw_phase_step_h),

        .ntw_phase_debug  (ntw_phase_debug),
        .ntw_cos_debug    (ntw_cos_debug),

        .amp_stp_ntw      (amp_setpoint_ntw), // final amplitude setpoint after excitation
        .phs_stp_ntw      (phs_setpoint_ntw)
    );

    wire pulse_val;
    pulse_gen #(.AW(32)) pulse(
        .clk        (dsp_clk),
        .trigger    (cbuf_sync),        // syncn with waveform
        .strobe     (cic_sample),       // CIC_BASE_PERIOD cycles per strobe
        .high_len   (pulse_high_len),   // unit: For ALSU: 8.73ns * 22 = 0.192 us
        .pulse_out  (pulse_val)
    );
    wire drive_on2 = pulse_mode ? pulse_val : 1'b1;  // non-interruptible
    wire drive_on1 = dac_permit ? drive_on2 : 1'b0;  // TBD with interlock
    assign dac_data_a_out = drive_on1 ? dac_out : 16'h0;
    assign dac_data_b_out = drive_on2 ? dac_out : 16'h0;

    wire [15:0] config_rom_out;
    config_romx config_romx(
        .clk    (lb_clk),
        .address(lb_addr[10:0]),
        .data   (config_rom_out));

    // ---------------------
    // Scalar register readback
    // ---------------------
    wire signed [14:0] err_out_amp_lb;
    wire signed [14:0] err_out_phs_lb;
    data_xdomain #(.size(30)) loop_err_xdomain (
        .clk_in   (dsp_clk), .gate_in  (1'b1),
        .data_in  ({err_out_amp, err_out_phs}),
        .clk_out  (lb_clk), .gate_out (),
        .data_out ({err_out_amp_lb, err_out_phs_lb})
    );

    wire [N_CH-1:0] inlk_status_lb;
    wire [N_CH-1:0] inlk_latch_lb;
    wire [N_CH-1:0] inlk_hi_lb;
    wire [N_CH-1:0] inlk_lo_lb;
    wire [0:0] inlk_permit_out_lb;
    data_xdomain #(.size(4*N_CH+1)) inlk_stat_xdomain (
        .clk_in   (dsp_clk), .gate_in  (1'b1),
        .data_in  ({inlk_permit_out, inlk_latch, inlk_status, inlk_hi, inlk_lo}),
        .clk_out  (lb_clk), .gate_out (),
        .data_out ({inlk_permit_out_lb, inlk_latch_lb, inlk_status_lb, inlk_hi_lb, inlk_lo_lb})
    );

    wire [2:0] arc_permit_raw_lb;
    wire [2:0] arc_permit_latch_lb;
    wire [0:0] arc_permit_sum_lb;
    data_xdomain #(.size(3+3+1)) arc_stat_xdomain (
        .clk_in   (dsp_clk), .gate_in  (1'b1),
        .data_in  ({arc_permit_sum, arc_permit_latch, arc_permit_raw}),
        .clk_out  (lb_clk), .gate_out (),
        .data_out ({arc_permit_sum_lb, arc_permit_latch_lb, arc_permit_raw_lb})
    );

    // ---------------------
    // Read-only address space decoding
    // ---------------------
    wire [31:0] git_rev_id = GIT_REV_ID;

    reg [LB_DW-1:0] lb_rdata_r=0;
    reg [LB_ADW-1:0] lb_addr_d1=0;
    reg [31:0] reg_bank_0=0;

    // LB read mux: Match READ_DELAY=3 in system.v
    always @(posedge lb_clk) begin
        case (lb_addr[3:0])
            4'h0: reg_bank_0 <= git_rev_id;
            4'h1: reg_bank_0 <= inlk_hi_lb;
            4'h2: reg_bank_0 <= inlk_lo_lb;
            4'h3: reg_bank_0 <= inlk_status_lb;
            4'h4: reg_bank_0 <= inlk_latch_lb;
            4'h5: reg_bank_0 <= inlk_permit_out_lb;
            4'h6: reg_bank_0 <= arc_permit_raw_lb;
            4'h7: reg_bank_0 <= arc_permit_latch_lb;
            4'h8: reg_bank_0 <= arc_permit_sum_lb;
            4'h9: reg_bank_0 <= err_out_amp_lb;
            4'ha: reg_bank_0 <= err_out_phs_lb;
            4'hc: reg_bank_0 <= amp_setpoint_ntw;
            4'hd: reg_bank_0 <= phs_setpoint_ntw;
            4'he: reg_bank_0 <= ntw_cos_debug;
            4'hf: reg_bank_0 <= ntw_phase_debug;
            default: reg_bank_0 <= 32'hfaceface;
        endcase
        lb_addr_d1 <= lb_addr;
        casez (lb_addr_d1)
            18'h3????: lb_rdata_r <= mirror_out_0;
            18'b00_1000_0???_????_????: lb_rdata_r <= config_rom_out;
            18'h10800: lb_rdata_r <= slow_cbuf_ready;
            18'h120??: lb_rdata_r <= lb_slow_rdata;
            18'h1300?: lb_rdata_r <= mon_amp_lb;
            18'h1301?: lb_rdata_r <= mon_phs_lb;
            18'h14???: lb_rdata_r <= adc_buf_out[0];
            18'h15???: lb_rdata_r <= adc_buf_out[1];
            18'h16???: lb_rdata_r <= adc_buf_out[2];
            18'h17???: lb_rdata_r <= adc_buf_out[3];
            18'h18???: lb_rdata_r <= adc_buf_out[4];
            18'h19???: lb_rdata_r <= adc_buf_out[5];
            18'h1a???: lb_rdata_r <= adc_buf_out[6];
            18'h1b???: lb_rdata_r <= adc_buf_out[7];
            18'h1c???: lb_rdata_r <= dac_buf_out[0];
            18'h1d???: lb_rdata_r <= dac_buf_out[1];
            18'h2????: lb_rdata_r <= cbuf_out;
            18'h???0?: lb_rdata_r <= reg_bank_0;
            default:   lb_rdata_r <= 32'hfaceface;
        endcase
    end

    assign lb_rdata = lb_rdata_r;
    assign hpa_permit_out = 1'b1;
    assign fast_permit_out = 1'b0; // inlk_permit_out

endmodule
