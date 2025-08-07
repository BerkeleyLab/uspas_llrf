/* CIC Wave Recorder + Interlock stream filter wrapper + synchronous diagnostics (slow_bridge)
   Generic waveform recording system comprised of:
   - Multichannel CIC filter with runtime selectable base sample rate and waveform
     sampling rate (cc_samp_per)
   - Double-buffered circular buffer that can be read through a local bus interface
*/

module cic_waves #(
    parameter integer N_CH=10,
    parameter integer N_ADC=8,
    parameter integer DW=16,            // raw data width for slow data
    parameter integer DWIQ=18,          // iq_data width per channel
    parameter integer MON_RW=24,        // result width
    parameter integer CBUF_DW=24,       // CCFilt output width; Must be 20 if using half-band filter
    parameter integer CBUF_AW=13,
    parameter integer CIC_SHIFT_BASE=7,
    parameter integer INLK_SHIFT_BASE=12
) (
    // dsp_clk domain
    // cic and inlk waves
    input                      dsp_clk,
    input                      dsp_reset,
    input                      iq_dval,     // Strobe signal for input samples
    input [2*N_CH*DWIQ-1:0]    iq_data,     // Flattened array of unprocessed data streams. CH0 in LSBs
    // slow bridge
    input [DW*N_ADC-1:0]       slow_bridge_data_in,     // flattened raw adc data to slow_bridge
    input                      slow_snap,
    input [63:0]               evr_timestamp,

    // Control registers
    input [6:0]                cic_wave_samp_per,
    input [N_CH-1:0]           cic_chan_keep,
    input [6:0]                cic_base_period,
    input [3:0]                cic_wave_shift,
    input [3:0]                inlk_wave_shift,
    input [15:0]               cbuf_post_delay,
    input [7:0]                dsp_tag,

    // triggers
    input                      wave_trig,
    input                      inlk_permit_in,

    output signed [15:0]       inlk_data,
    output                     inlk_dval,
    output                     inlk_last,

    // lb_clk domain
    input                      lb_clk,
    input                      lb_read,
    input  [17:0]              lb_addr,
    output                     cbuf_sync,        // single-cycle when buffer starts/ends
    output                     cbuf_transferred, // single-cycle when a buffer has been
                                            // handed over for reading;
                                            // one cycle delayed from buf_sync
    // Circular Buffer data readout
    input                      cbuf_buf_flip,
    output                     cbuf_ready,
    output [CBUF_DW-1:0]       cbuf_out,

    output                     slow_ready,
    output [15:0]              slow_rdata
);

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
        .base_period    (cic_base_period),
        .wave_samp_per  (cic_wave_samp_per),
        .cic_sample     (cic_sample),
        .sample_wave    (cc_sample)
    );

    // XXX needs test
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

    // expand cic_chan_keep channel to IQ masks
    wire di_stb_out;
    wire [MON_RW-1:0] di_sr_out;
    wire [2*N_CH-1:0] chan_keep_iq;
    genvar ch;
    generate for (ch=0; ch<N_CH; ch=ch+1)
        begin: gen_chan_keep
            assign chan_keep_iq[2*ch] = cic_chan_keep[ch];
            assign chan_keep_iq[2*ch+1] = cic_chan_keep[ch];
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
        .d_in         (iq_data),   // Flattened array of unprocessed IQ streams. CH0 in LSBs
        .cic_sample   (cic_sample),

        // Post-integrator conveyor belt tap
        .di_stb_out   (di_stb_out),
        .di_sr_out    (di_sr_out),

        .cc_sample    (cc_sample),
        .cc_shift     (cic_wave_shift), // controls scaling of filter result

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
        .buf_stb      (cbuf_buf_flip),
        .buf_enable   (cbuf_ready),
        .buf_read_addr(lb_addr[CBUF_AW-1:0]),
        .buf_d_out    (cbuf_out)
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
       .shift    (inlk_wave_shift),
       .result   (inlk_data),     // signed filtered and scaled result
       .strobe   (inlk_dval)
    );

    reg [8:0] inlk_count=0;
    always @(posedge dsp_clk) inlk_count <= inlk_dval ? inlk_count + 1 : 0;
    assign inlk_last = inlk_count == (2*N_CH-1);

    // ---------------------
    // Instantiate diagnostics buffer
    //     synchronized with waveform
    //     for adc_min / adc_max, timestamp, waveform status,
    //     and snap for validation of a waveform if register changed in between
    // ---------------------
    wire [15:0] cbuf_stat2_lsb = cbuf_stat2;
    slow_bridge_shell #(.AW(7), .DW(DW), .N_CH(N_ADC)) slow_bridge (
        .lb_clk         (lb_clk),
        .lb_addr        (lb_addr[6:0]),
        .lb_read        (lb_read),
        .lb_rdata       (slow_rdata),
        .tag            (dsp_tag),

        .dsp_clk        (dsp_clk),
        .buf_start      (cbuf_start),
        .buf_sync       (cbuf_sync),
        .buf_stat1      (cbuf_stat1),
        .buf_stat2      (cbuf_stat2_lsb),
        .buf_count      (cbuf_count),
        .buf_ready      (cbuf_ready),
        .data_in        (slow_bridge_data_in),
        .evr_timestamp  (evr_timestamp),

        .slow_snap      (slow_snap),
        .slow_ready     (slow_ready)
    );

endmodule