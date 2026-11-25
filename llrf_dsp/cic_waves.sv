/* CIC Wave Recorder + Interlock stream filter wrapper + synchronous diagnostics (slow_bridge)
   Generic waveform recording system comprised of:
   - Multichannel CIC filter with runtime selectable base sample rate and waveform
     sampling rate (cc_samp_per)
   - Double-buffered circular buffer that can be read through a local bus interface

   iq_data, slow_bridge_data_in and slow_aux are arrays (iq_data: I of channel
   n at 2*n, Q at 2*n+1; slow_aux: the first word of the slow data first). The
   control registers are one cic_cfg_t. N_CH is llrf_shell_pkg's: cic_cfg_t's
   chan_keep has that many bits.
*/
`default_nettype none

module cic_waves #(
    parameter integer N_CH=10,
    parameter integer N_ADC=8,
    parameter integer DW=16,            // raw data width for slow data
    parameter integer DWIQ=18,          // iq_data width per channel
    parameter integer MON_RW=24,        // result width
    parameter integer CBUF_DW=24,       // CCFilt output width; Must be 20 if using half-band filter
    parameter integer CBUF_AW=13,
    parameter integer CIC_SHIFT_BASE=7,
    parameter integer INLK_SHIFT_BASE=12,
    parameter integer N_SLOW_AUX=1      // 16-bit words appended to the slow data
) (
    // dsp_clk domain
    // cic and inlk waves
    input wire                 dsp_clk,
    input wire                 dsp_reset,
    input wire                 iq_dval,     // Strobe signal for input samples
    input wire signed [DWIQ-1:0] iq_data [2*N_CH],  // unprocessed streams: I of channel n at 2*n, Q at 2*n+1
    // slow bridge
    input wire signed [DW-1:0]   slow_bridge_data_in [N_ADC],  // raw adc data to slow_bridge
    input wire                 slow_snap,
    input wire [63:0]               evr_timestamp,
    input wire [DW-1:0]       slow_aux [N_SLOW_AUX],  // slow data words after the cycle counter, first word first; snapshot like evr_timestamp

    // Control registers
    input wire llrf_shell_pkg::cic_cfg_t cic_cfg,

    // triggers
    input wire                 wave_trig,
    input wire                 cbuf_free_run,   // record continuously, ignore wave_trig
    input wire                 record_en,

    output logic signed [15:0]       inlk_data,
    output logic               inlk_dval,
    output logic               inlk_last,

    // lb_clk domain
    input wire                 lb_clk,
    input wire                 lb_read,
    input wire [17:0]              lb_addr,
    output logic               cbuf_sync,        // single-cycle when buffer starts/ends
    output logic               cbuf_transferred, // single-cycle when a buffer has been
                                            // handed over for reading;
                                            // one cycle delayed from buf_sync
    // Circular Buffer data readout
    input wire                 cbuf_buf_flip,
    output logic               cbuf_ready,
    output logic [CBUF_DW-1:0]       cbuf_out,

    output logic               slow_ready,
    output logic [15:0]              slow_rdata
);

    // the Verilog blocks below take flattened buses, channel 0 in the LSBs
    // (slow_aux: first word in the MSBs, as slow_bridge_shell reads it)
    logic [2*N_CH*DWIQ-1:0]   iq_data_flat;
    logic [DW*N_ADC-1:0]      slow_data_flat;
    logic [DW*N_SLOW_AUX-1:0] slow_aux_flat;
    always_comb begin
        for (int n = 0; n < 2*N_CH; n++) iq_data_flat[DWIQ*n +: DWIQ] = iq_data[n];
        for (int n = 0; n < N_ADC; n++) slow_data_flat[DW*n +: DW] = slow_bridge_data_in[n];
        for (int n = 0; n < N_SLOW_AUX; n++) slow_aux_flat[DW*(N_SLOW_AUX-1-n) +: DW] = slow_aux[n];
    end
    // in an initial block: Vivado 2022.1 takes $error only there (UG901)
    if (N_CH != llrf_shell_pkg::N_CH) begin : bad_n_ch
        initial $error("cic_waves: N_CH must be llrf_shell_pkg::N_CH, the width of cic_cfg_t.chan_keep");
    end

    wire [15:0] cbuf_count;
    wire [15:0] cbuf_stat1;
    wire [CBUF_AW-1:0] cbuf_stat2;
    // ---------------------
    // Instantiate Sampler
    // ---------------------
    wire cic_sample, cc_sample;

    cic_timing cic_timing_i (
        .clk            (dsp_clk),
        .reset          (dsp_reset),
        .base_period    (cic_cfg.base_period),
        .wave_samp_per  (cic_cfg.wave_samp_per),
        .cic_sample     (cic_sample),
        .sample_wave    (cc_sample)
    );

    // -- Waveform freeze logic
    // Stop the circle buffer cic_cfg.post_delay buffer syncs after record_en
    // drops; cic_cfg.post_delay=0 disables the freeze. The stop is gated by
    // ~record_en and a non-zero delay so cic_cfg.post_delay writes (and the
    // power-up default of 0) never produce a spurious fault record.
    logic [16:0] delay_cnt=0;
    wire       cbuf_delay_stop = (delay_cnt >= {1'b0, cic_cfg.post_delay});
    logic        cbuf_delay_stop1=1;
    wire cbuf_stop = ~record_en & (|cic_cfg.post_delay) &
                     cbuf_delay_stop & ~cbuf_delay_stop1;
    always_ff @(posedge dsp_clk) begin
        cbuf_delay_stop1 <= cbuf_delay_stop;
        delay_cnt <= record_en ? 0 : cbuf_delay_stop ? delay_cnt : delay_cnt + cbuf_sync;
    end

    // Stop writing the circle buffer once it is full until the next
    // wave_trig, so triggered modes record one buffer per trigger.
    // cbuf_free_run keeps writing;
    logic stream_valid=1'b1;
    always_ff @(posedge dsp_clk) begin
        if (dsp_reset | cbuf_free_run | wave_trig) stream_valid <= 1'b1;
        else if (cbuf_sync) stream_valid <= 1'b0;
    end

    // expand cic_cfg.chan_keep channel to IQ masks
    wire di_stb_out;
    wire [MON_RW-1:0] di_sr_out;
    wire [2*N_CH-1:0] chan_keep_iq;
    genvar ch;
    generate for (ch=0; ch<N_CH; ch=ch+1)
        begin: gen_chan_keep
            assign chan_keep_iq[2*ch] = cic_cfg.chan_keep[ch];
            assign chan_keep_iq[2*ch+1] = cic_cfg.chan_keep[ch];
        end
    endgenerate

    cic_wave_recorder #(
        .n_chan        (2*N_CH),
        .di_dwi        (DWIQ),  // data width
        .di_rwi        (MON_RW),  // result width
                        // Difference between above two widths should be N*log2 of the maximum number
                        // of samples per CIC sample, where N=2 is the order of the CIC filter.
        .di_noise_bits (0),
        .cc_outw       (CBUF_DW),       // CCFilt output width; Must be 20 if using half-band filter
        .cc_halfband   (0),
        .cc_shift_base (CIC_SHIFT_BASE),   // Bits to discard from previous acc step
        .buf_dw        (CBUF_DW),
        .buf_aw        (CBUF_AW),
        .lsb_mask      (1),             // LSB of channel mask is CH0
        .buf_auto_flip (0)
    ) cic_wave_recorder (
        .iclk         (dsp_clk),
        .reset        (dsp_reset),
        .stb_in       (iq_dval),
        .d_in         (iq_data_flat),
        .cic_sample   (cic_sample),

        // Post-integrator conveyor belt tap
        .di_stb_out   (di_stb_out),
        .di_sr_out    (di_sr_out),

        .cc_sample    (cc_sample),
        .cc_shift     (cic_cfg.wave_shift), // controls scaling of filter result

        // Channel selector controls
        .chan_mask    (chan_keep_iq),     // Bitmask of channels to record. chan_mask[0] -> CH0

        // Circular Buffer control and statistics
        .oclk         (lb_clk),
        // gates circle buffer writes on channel burst boundaries only,
        // the interlock stream (di_sr_out) keeps running
        .buf_write    (stream_valid),

        .buf_sync     (cbuf_sync),            // single-cycle when buffer starts/ends
        .buf_transferred(cbuf_transferred),    // single-cycle when a buffer has been
        .buf_stop     (cbuf_stop),             // single-cycle - interrupts cbuf writing
        .buf_count    (cbuf_count),
        .buf_stat2    (cbuf_stat2),         // includes fault bit
        .buf_stat     (cbuf_stat1),         // includes fault bit(), and (if set) the last valid location
        .debug_stat   (),            // {stb_in(), boundary(), btest(), wbank(), rbank(), wr_addr}

        // Circular Buffer data readout
        .buf_stb      (cbuf_buf_flip),
        .buf_enable   (cbuf_ready),
        .buf_read_addr(lb_addr[CBUF_AW-1:0]),
        .buf_d_out    (cbuf_out),

        // decimated waveform stream: unused
        .wave_gate_out(),
        .wave_dval_out(),
        .wave_data_out()
    );


    // ---------------------
    // For interlock stream, fixed dw=16, fixed decimation.
    // ---------------------
    ccfilt #(
       .dw         (MON_RW),
       .outw       (16),
       .shift_base (INLK_SHIFT_BASE),
       .dsr_len    (2*N_CH),
       .use_hb     (0)
    ) inlk_ccfilt (
       .clk      (dsp_clk),
       .reset    (dsp_reset),
       .sr_in    (di_sr_out),
       .sr_valid (di_stb_out),    // fixed wave_samp_per = 1
       .shift    (cic_cfg.inlk_wave_shift),
       .result   (inlk_data),     // signed filtered and scaled result
       .strobe   (inlk_dval)
    );

    logic [8:0] inlk_count=0;
    always_ff @(posedge dsp_clk) inlk_count <= inlk_dval ? inlk_count + 1 : 0;
    localparam integer INLK_LAST = 2*N_CH-1;
    assign inlk_last = inlk_count == INLK_LAST[8:0];

    // ---------------------
    // Instantiate diagnostics buffer
    //     synchronized with waveform
    //     for adc_min / adc_max, timestamp, waveform status,
    //     and snap for validation of a waveform if register changed in between
    // ---------------------
    wire [15:0] cbuf_stat2_lsb = cbuf_stat2;
    slow_bridge_shell #(.AW(7), .DW(DW), .N_CH(N_ADC), .N_AUX(N_SLOW_AUX)) slow_bridge (
        .lb_clk         (lb_clk),
        .lb_addr        (lb_addr[6:0]),
        .lb_read        (lb_read),
        .lb_rdata       (slow_rdata),
        .tag            (cic_cfg.dsp_tag),

        .dsp_clk        (dsp_clk),
        .buf_sync       (cbuf_sync),
        .buf_stat1      (cbuf_stat1),
        .buf_stat2      (cbuf_stat2_lsb),
        .buf_count      (cbuf_count),
        .buf_ready      (cbuf_ready),
        .data_in        (slow_data_flat),
        .evr_timestamp  (evr_timestamp),
        .aux_data       (slow_aux_flat),

        .slow_snap      (slow_snap),
        .slow_ready     (slow_ready)
    );

endmodule

`default_nettype wire
