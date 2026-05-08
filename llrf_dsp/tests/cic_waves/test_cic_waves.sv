// Test wrapper for cic_waves with expanded iq_data array inputs.
// Exposes parameters N_CH, N_ADC, CBUF_AW, and other core settings.


module test_cic_waves
    import test_cic_waves_pkg::*;
#(
    parameter int N_CH = 10,
    parameter int N_ADC = 8,
    parameter int DW = 16,
    parameter int DWIQ = 18,
    parameter int MON_RW = 24,
    parameter int CBUF_DW = 24,
    parameter int CBUF_AW = 13,
    parameter int CIC_SHIFT_BASE = 7,
    parameter int INLK_SHIFT_BASE = 12,
    localparam addr_t P_ADDR_CBUF_DATA_BASE = ADDR_CBUF_DATA_BASE,
    localparam addr_t P_ADDR_CBUF_READY = ADDR_CBUF_READY,
    localparam addr_t P_ADDR_CBUF_TRANSFERED = ADDR_CBUF_TRANSFERED,
    localparam addr_t P_ADDR_CBUF_FLIP = ADDR_CBUF_FLIP
) (
    // DSP domain interface
    input                      dsp_clk,
    input                      dsp_reset,

    input                      iq_dval,
    input signed [DWIQ-1:0]    iq_data [0:2*N_CH-1],      // CH0..CH(2*N_CH-1)

    input  signed [DW-1:0]     slow_bridge_data_in [0:N_ADC-1],
    input      [63:0]          evr_timestamp,

    input      [6:0]           cic_wave_samp_per,
    input      [N_CH-1:0]      cic_chan_keep,
    input      [6:0]           cic_base_period,
    input      [3:0]           cic_wave_shift,
    input      [3:0]           inlk_wave_shift,
    input      [15:0]          cbuf_post_delay,
    input      [7:0]           dsp_tag,

    input      [2:0]           wave_trig_sel,

    input                      ext_trig,
    input                      record_en,

    output signed [15:0]       inlk_data,
    output                     inlk_dval,
    output                     inlk_last,

    // LB interface
    input                      lb_clk,
    input                      lb_write,
    input                      lb_read,
    input                      lb_rvalid,
    input      [17:0]          lb_addr,
    input      [31:0]          lb_wdata,
    output     [31:0]          lb_rdata,

    output     [CBUF_DW-1:0]   cbuf_out,
    output                     cbuf_ready,
    output                     cbuf_sync,
    output                     cbuf_transferred,

    output                     slow_ready,
    output     [15:0]          slow_rdata
);

    // Pack flattened iq_data for cic_waves
    wire [2*N_CH*DWIQ-1:0] iq_data_flat;
    genvar ch;
    generate
        for (ch = 0; ch < 2*N_CH; ch = ch + 1) begin : gen_iq_flat
            assign iq_data_flat[DWIQ*ch +: DWIQ] = iq_data[ch];
        end
    endgenerate

    // Pack slow bridge data in flatten vector
    wire [DW*N_ADC-1:0] slow_bridge_data_in_flat;
    generate
        for (ch = 0; ch < N_ADC; ch = ch + 1) begin : gen_slow_flat
            assign slow_bridge_data_in_flat[DW*ch +: DW] = slow_bridge_data_in[ch];
        end
    endgenerate

    logic cbuf_buf_flip;
    logic we_cbuf_buf_flip;
    assign we_cbuf_buf_flip = lb_write & (lb_addr==ADDR_CBUF_FLIP);
    always_ff @( lb_clk ) begin : lb_write_block
        cbuf_buf_flip <= we_cbuf_buf_flip ? lb_wdata[0] : 1'b0;
    end

    // ---------------------
    // Triggering logic
    // ---------------------
    localparam [2:0] WAVE_TRIG_ALWAYS= 3'd4,  // internal trigger, cbuf continuous
                     WAVE_TRIG_INT   = 3'd0,  // internal trigger
                     WAVE_TRIG_EXT   = 3'd1;  // external trigger
    localparam int INT_TRIG_PERIOD = 1000;
    // trigger flags in dsp_clk domain
    logic int_trig;
    logic wave_trig_i;
    // internal trigger
    logic [31:0] int_trig_cnt = 0;
    assign int_trig = (int_trig_cnt == INT_TRIG_PERIOD - 1);
    always_ff @(posedge dsp_clk) begin
        int_trig_cnt <= (dsp_reset || int_trig) ? 0 : int_trig_cnt + 1'b1;
    end
    always_ff @(posedge dsp_clk) begin
        case (wave_trig_sel)
            WAVE_TRIG_INT:  wave_trig_i <= int_trig;
            WAVE_TRIG_EXT:  wave_trig_i <= ext_trig;
            default: begin
                wave_trig_i <= cbuf_sync;
            end
        endcase
    end

    cic_waves #(
        .N_CH          (N_CH),
        .N_ADC         (N_ADC),
        .DW            (DW),
        .DWIQ          (DWIQ),
        .MON_RW        (MON_RW),
        .CBUF_DW       (CBUF_DW),
        .CBUF_AW       (CBUF_AW),
        .CIC_SHIFT_BASE(CIC_SHIFT_BASE),
        .INLK_SHIFT_BASE(INLK_SHIFT_BASE)
    ) dut (
        .dsp_clk            (dsp_clk),
        .dsp_reset          (dsp_reset),
        .iq_dval            (iq_dval),
        .iq_data            (iq_data_flat),

        .slow_bridge_data_in(slow_bridge_data_in_flat),
        .slow_snap          (cbuf_transferred),
        .evr_timestamp      (evr_timestamp),

        .cic_wave_samp_per  (cic_wave_samp_per),
        .cic_chan_keep      (cic_chan_keep),
        .cic_base_period    (cic_base_period),
        .cic_wave_shift     (cic_wave_shift),
        .inlk_wave_shift    (inlk_wave_shift),
        .cbuf_post_delay    (cbuf_post_delay),
        .dsp_tag            (dsp_tag),

        .wave_trig          (wave_trig_i),
        .record_en     (record_en),

        .inlk_data          (inlk_data),
        .inlk_dval          (inlk_dval),
        .inlk_last          (inlk_last),

        .lb_clk             (lb_clk),
        .lb_read            (lb_read),
        .lb_addr            (lb_addr),
        .cbuf_sync          (cbuf_sync),
        .cbuf_transferred   (cbuf_transferred),

        .cbuf_buf_flip      (cbuf_buf_flip),
        .cbuf_ready         (cbuf_ready),
        .cbuf_out           (cbuf_out),

        .slow_ready         (slow_ready),
        .slow_rdata         (slow_rdata)
    );

    localparam addr_t ADDR_CBUF_DATA_END  = ADDR_CBUF_DATA_BASE + ((1<<CBUF_AW) - 1);
    logic [31:0] rd_data;
    logic [17:0] rd_addr;
    logic addr_hit_array;
    assign addr_hit_array = addr_in_array(rd_addr, ADDR_CBUF_DATA_BASE, ADDR_CBUF_DATA_END);

    always_ff @( lb_clk ) begin : lb_read_block
        rd_addr <= lb_addr;
        case (rd_addr)
            ADDR_CBUF_READY:      rd_data <= cbuf_ready;
            ADDR_CBUF_TRANSFERED: rd_data<= cbuf_transferred;
            default:  begin
                if (addr_hit_array) begin
                    rd_data <= cbuf_out;
                end else begin
                    rd_data <= 32'hDEAD_BEEF;
                end
            end
        endcase
    end
    assign lb_rdata = rd_data;
endmodule
