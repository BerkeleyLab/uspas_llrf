module test_llrf_shell #(
    parameter integer FDBK_ADC = 0,
    parameter integer DW = 16,
    parameter integer N_ADC = 8,
    parameter integer N_DAC = 2,
    parameter integer DWLO = 18,
    parameter integer LB_ADW = 18,
    parameter integer CBUF_AW = 6,
    parameter integer SIG_BUF_AW = 6
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
    output signed [DW-1:0] dac_array_out [N_DAC],

    // ---------------------
    // GT transceiver interface
    // ---------------------
    input                gt_rxclk,
    input [15:0]         gt_rxdata,
    input [1:0]          gt_rxcharisk
);

    logic [N_ADC*DW-1:0] adc_data_in;
    genvar ch;
    generate for (ch=0; ch<N_ADC; ch=ch+1) begin: ch_map_i
        assign adc_data_in[DW*ch +: DW] = adc_array_in[ch];
    end endgenerate


    llrf_shell #(
        .SIG_BUF_AW     (SIG_BUF_AW),
        .CBUF_AW        (CBUF_AW)
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

        .gt_rxclk,
        .gt_rxdata,
        .gt_rxcharisk
    );
endmodule
