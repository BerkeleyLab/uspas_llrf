// LEMP shell (plan 9c) in the base TB wrapper, plus the LEMP ports
module test_llrf_shell #(
    parameter integer FDBK_ADC = 0,
    parameter integer DW = 16,
    parameter integer N_ADC = 8,
    parameter integer N_DRIVE = 2,
    parameter integer DWLO = 18,
    parameter integer LB_ADW = 18,
    parameter integer CBUF_AW = 6,
    parameter integer SIG_BUF_AW = 6,
    parameter integer F_DSP_HZ = 125_000_000,  // set small in sim to shorten the arc_inlk 0.5 s pulse
    parameter integer EVR_TRIG_WINDOW = 200    // LEMP: 23800, shortened for sim
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
    input                  dsp_clk,
    input signed  [DW-1:0] adc_array_in  [N_ADC],
    input                  dac_clk,
    output signed [DW-1:0] dac_array_out [N_DRIVE],

    // ---------------------
    // GT transceiver interface
    // ---------------------
    input                gt_rxclk,
    input [15:0]         gt_rxdata,
    input [1:0]          gt_rxcharisk,

    // ---------------------
    // ARC detector outputs
    // ---------------------
    output [2:0]         arc_test_out,
    output               arc_reset_out,

    // ---------------------
    // LEMP
    // ---------------------
    input  [7:0]         intlk_latch_in,
    output [3:0]         pmod_trigs,
    input                sssb_alarm,
    input                sssb_rf_status,
    output               sssb_rf_switch_out,
    output               sssb_rst_out,
    output [3:0]         evr_events,
    output               dds_reset_out,
    output [DWLO-1:0]    dds_cos,
    output [DWLO-1:0]    dds_sin
);

    logic [N_ADC*DW-1:0] adc_data_in;
    genvar ch;
    generate for (ch=0; ch<N_ADC; ch=ch+1) begin: ch_map_i
        assign adc_data_in[DW*ch +: DW] = adc_array_in[ch];
    end endgenerate


    llrf_shell #(
        .SIG_BUF_AW     (SIG_BUF_AW),
        .CBUF_AW        (CBUF_AW),
        .F_DSP_HZ       (F_DSP_HZ),
        .EVR_TRIG_WINDOW (EVR_TRIG_WINDOW)
    ) llrf_shell (
        .lb_clk,
        .lb_write,
        .lb_addr,
        .lb_wdata,
        .lb_rdata,
        .lb_read,
        .lb_rvalid,
        .lb_prefill     (1'b0),

        .dsp_clk,
        .adc_data_in,
        .dac_clk,
        .dac_data_a_out (dac_array_out[0]),
        .dac_data_b_out (dac_array_out[1]),

        .drive_permit_in (1'b1),
        .slow_permit_in  (1'b1),
        .arc_permit_in   (3'b111),
        .arc_test_out,
        .arc_reset_out,

        .gt_rxclk,
        .gt_rxdata,
        .gt_rxcharisk,
        .ext_trigger     (1'b0),

        .intlk_latch_in,
        .pmod_trigs,
        .sssb_alarm,
        .sssb_rf_status,
        .sssb_rf_switch_out,
        .sssb_rst_out,
        .evr_events,
        .dds_reset_out,
        .dds_cos,
        .dds_sin
    );
endmodule
