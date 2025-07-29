module test_llrf_shell #(
    parameter integer FDBK_ADC = 0,
    parameter integer DW = 16,
    parameter integer N_ADC = 8,
    parameter integer N_DAC = 2,
    parameter integer DWLO = 18,
    parameter integer LB_ADW = 18,
    parameter integer CBUF_AW = 6,
    parameter integer CBUF_DW = 24,
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
    output signed [DW-1:0] dac_array_out [N_DAC],

    // ---------------------
    // GTX transceiver interface
    // ---------------------
    input                gtx_rxclk,
    input [15:0]         gtx_rxdata,
    input [1:0]          gtx_rxcharisk
);

    logic [N_ADC*DW-1:0] adc_data_in;
    genvar ch;
    generate for (ch=0; ch<N_ADC; ch=ch+1) begin: ch_map_i
        assign adc_data_in[DW*ch +: DW] = adc_array_in[ch];
    end endgenerate;


    logic [N_DAC*DW-1:0] dac_flat_out;
    generate for (ch=0; ch<N_DAC; ch=ch+1) begin: ch_map_o
        assign dac_array_out[ch] = dac_flat_out[DW*ch +: DW];
    end endgenerate;

    llrf_shell #(
        .SIG_BUF_AW     (SIG_BUF_AW),
        .CBUF_AW        (CBUF_AW),
        .CBUF_DW        (CBUF_DW)
    ) dut(
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
        .dac_data_a_out (dac_array_out[0]),
        .dac_data_b_out (dac_array_out[1]),

        .drive_permit_in (1'b1),
        .slow_permit_in  (1'b1),
        .arc_permit_in   (3'b111),

        .gtx_rxclk,
        .gtx_rxdata,
        .gtx_rxcharisk,

        .etrig_pulse_cnt    (16'd0),
        .etrig_pulse        (1'b0),
        .etrig_pulse_delay  (1'b0)
    );
endmodule