// Aux info synchronized with waveform
// total n_words = 5 + 2*N_CH must be < 2**AW, address starting from 0x11
// AW >=6 when N_CH==8
// content see static_regmap.json, dsp_slow_*
// {buf_stat1, buf_stat2, buf_count, 8'h0, tag, 8'h0, tag_old, sig_min_max, evr_timestamp, timestamp}
module slow_bridge_shell #(
    parameter AW    = 7,
    parameter N_CH  = 8,
    parameter DW    = 16
) (
    // 32-bit local bus (slave)
    input           lb_clk,
    input [AW-1:0]  lb_addr,
    input           lb_read,
    output [DW-1:0] lb_rdata,
    input [7:0]     tag,
    // circle buf, dsp_clk domain
    input           dsp_clk,

    input           buf_sync,  // start / end of current buffer
    input [15:0]    buf_stat1,
    input [15:0]    buf_stat2,
    input [15:0]    buf_count,
    input           buf_ready,

    input [DW*N_CH-1:0] data_in,

    input [63:0]    evr_timestamp, // N.B. evr_timestamp must be aligned with start of buffer

    input           slow_snap, // Typically 'buf_transferred' so we save auxiliary data
                               // pertaining to the just-completed buffer
    output          slow_ready
);
    reg running=0, shifting=0;
    reg [AW-1:0] write_addr=0;
    always @(posedge dsp_clk) begin
        if (slow_snap | &write_addr) running <= slow_snap;
        if (running) write_addr <= buf_sync ? 0 : write_addr+1; // TODO: Explain use of buf_sync
        shifting <= running & |write_addr[AW-1:4]; // starts from addr=0x11
    end

    wire [DW-1:0] slow_data_in;
    dpram #(.aw(AW), .dw(DW)) ram(
        .clka   (dsp_clk),
        .addra  (write_addr),
        .dina   (slow_data_in),
        .wena   (running),
        .clkb   (lb_clk),
        .addrb  (lb_addr),
        .doutb  (lb_rdata)
    );
    wire slow_op = slow_snap | shifting;

    localparam SR_LEN1 = 5*DW;
    localparam SR_LEN2 = 2*N_CH*DW;

    // Compute raw ADC and DAC min/max
    wire [N_CH*DW-1:0] sig_min;
    wire [N_CH*DW-1:0] sig_max;
    // assign adc_min = {adc_min[0], adc_min[1], ..., adc_min[7]};
    // assign adc_max = {adc_max[0], adc_max[1], ..., adc_max[7]};
    wire [SR_LEN2-1:0] sig_min_max = {sig_min, sig_max};
    genvar ix;
    generate for (ix=0; ix<N_CH; ix=ix+1) begin: gen_minmax
        minmax #(.width(DW)) mm_i (
            .clk    (dsp_clk),
            .xin    (data_in[(DW*ix)+:DW]),
            .reset  (slow_snap),
            .xmin   (sig_min[DW*(N_CH-ix-1) +: DW]),
            .xmax   (sig_max[DW*(N_CH-ix-1) +: DW])
        );
        end
    endgenerate

    // Cycle counter
    wire [7:0] timestamp;
    timestamp ts (
        .clk        (dsp_clk),
        .aux_trig   (1'b0),
        .slow_op    (slow_op),
        .slow_snap  (slow_snap),
        .shift_in   (8'b0),
        .shift_out  (timestamp)
    );

    wire [DW-1:0] timestamp_pad = {8'h0, timestamp};
    // Double-buffer evr_timestamp so we can simultaneously snapshot current and transfer previous
    reg [63:0] evr_ts_snap1, evr_ts_snap2;
    reg evr_ts_rd=0;
    always @(posedge dsp_clk) begin
        if (buf_sync) begin
            if (evr_ts_rd^slow_snap) evr_ts_snap2 <= evr_timestamp;
            else                     evr_ts_snap1 <= evr_timestamp;
        end
        if (slow_snap) evr_ts_rd <= ~evr_ts_rd;

        // Shift out EVR timestamp MSB word first; follow with local cycle counter (timestamp_pad)
        if (shifting) begin
            if ( evr_ts_rd) evr_ts_snap1 <= {evr_ts_snap1[64-DW-1:0], timestamp_pad};
            if (!evr_ts_rd) evr_ts_snap2 <= {evr_ts_snap2[64-DW-1:0], timestamp_pad};
        end
    end
    wire [DW-1:0] evr_ts_word = evr_ts_rd ? evr_ts_snap1[64-DW +:DW] : evr_ts_snap2[64-DW +:DW];

    reg [7:0] tag_old=0;
    wire [SR_LEN1-1:0] slow_sr_data = {buf_stat1, buf_stat2, buf_count, 8'h0, tag, 8'h0, tag_old};
    wire [DW-1:0] slow_dsp_data;
    // from cmoc/slow_bridge.v
    reg [SR_LEN1-1:0] slow_sr1=0;
    reg [SR_LEN2-1:0] slow_sr2=0;
    always @(posedge dsp_clk) begin
        if (slow_op) begin
            slow_sr1 <= slow_snap ? slow_sr_data : {slow_sr1[SR_LEN1-DW-1:0], slow_dsp_data};
            slow_sr2 <= slow_snap ?  sig_min_max : {slow_sr2[SR_LEN2-DW-1:0], evr_ts_word};
            if (slow_snap) tag_old <= tag;
        end
    end
    assign slow_dsp_data = slow_sr2[SR_LEN2-DW +:DW];
    assign slow_data_in  = slow_sr1[SR_LEN1-DW +:DW];
    // XXX formerly mixed domains; simulate to make sure new version's latency is OK
    reg running_lb=0;
    always @(posedge lb_clk) running_lb <= running;
    assign slow_ready = buf_ready & ~running_lb;

endmodule
