module test_llrf_shell #(
    parameter integer FDBK_ADC = 0,
    parameter integer DW = 16,
    parameter integer N_ADC = 8,
    parameter integer N_DRIVE = 2,
    parameter integer DWLO = 18,
    parameter integer LB_ADW = 18,
    parameter integer CBUF_AW = 6,
    parameter integer SIG_BUF_AW = 6,
    parameter integer F_DSP_HZ = 125_000_000  // set small in sim to shorten the arc_inlk 0.5 s pulse
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
    output               arc_reset_out
);

    logic [N_ADC*DW-1:0] adc_data_in;
    genvar ch;
    generate for (ch=0; ch<N_ADC; ch=ch+1) begin: ch_map_i
        assign adc_data_in[DW*ch +: DW] = adc_array_in[ch];
    end endgenerate


    // the shell's typed ports, from this wrapper's flat ones (cocotb drives these)
    llrf_shell_pkg::lb_req_t lb_req;
    assign lb_req = '{write: lb_write, read: lb_read, rvalid: lb_rvalid, prefill: 1'b0,
                      addr: lb_addr, wdata: lb_wdata};
    llrf_shell_pkg::dac_t [1:0] dac_out;
    assign dac_array_out[0] = dac_out[0];
    assign dac_array_out[1] = dac_out[1];

    llrf_shell #(
        .SIG_BUF_AW     (SIG_BUF_AW),
        .CBUF_AW        (CBUF_AW),
        .F_DSP_HZ       (F_DSP_HZ)
    ) llrf_shell (
        .lb_clk,
        .lb_req,
        .lb_rdata,

        .dsp_clk,
        .adc_in         (adc_data_in),
        .dac_clk,
        .dac_out,

        .drive_permit_in (1'b1),
        .slow_permit_in  (1'b1),
        .arc_permit_in   (3'b111),
        .arc_test_out,
        .arc_reset_out,

        .gt_rxclk,
        .gt_rxdata,
        .gt_rxcharisk,

        .design_in      ('0),
        .design_out     ()
    );
endmodule
