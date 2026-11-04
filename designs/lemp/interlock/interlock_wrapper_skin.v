module interlock_skin #(
    parameter integer NI = 8,
    parameter integer LB_DW = 32,
    parameter integer LB_ADW = 18,
    parameter integer DWLO = 18,
    parameter DW = 16
) (
    input                clk,
    // ---------------------
    // Localbus interface
    // ---------------------
    input               lb_clk,
    input  [LB_ADW-1:0] lb_addr,
    input               lb_write,
    input               lb_read,
    input               lb_rvalid,
    input  [LB_DW-1:0]  lb_wdata,
    output [LB_DW-1:0]  lb_rdata,
    // ---------------------
    // other HW I/O
    // ---------------------
    output              mod_permit_out,
    input               status_modulator,
    // ---------------------
    // Interlock interface
    // ---------------------
    input                   dds_reset,
    input signed [DWLO-1:0] dds_cos,
    input signed [DWLO-1:0] dds_sin,
    input                   dsp_dac_pll_locked, // dsp_dac_pll_locked signal represents if the adc_clk is correct i.e. if the PLL is locked
    input signed [DW-1:0]   kly_rev_in,  //
    input signed [DW-1:0]   beam_vol_in, //
    input signed [DW-1:0]   beam_cur_in, //
    // Interlock outputs
    output [NI-1:0]         intlk_fault,   // Current fault when '1'
    output [NI-1:0]         intlk_latch,   // Latched fault when '1'
    output [NI-1:0]         intlk_firstf,  // First fault indication
    output                  intlk_trig     // Single-cycle start-of-fault indicator
);


// Localbus
(* magic_cdc *) reg [LB_ADW-1:0]  lb_addr_r=0;
(* magic_cdc *) reg lb_write_r=0, lb_read_r=0, lb_rvalid_r=0;
(* magic_cdc *) reg [31:0]        lb_wdata_r=0;
(* magic_cdc *) reg [31:0]        lb_rdata_r=0;
/*           */ wire [31:0]       lb_rdata_x;
always @(posedge lb_clk) begin
	lb_addr_r <= lb_addr;
	lb_write_r <= lb_write;
	lb_read_r <= lb_read;
	lb_rvalid_r <= lb_rvalid;
	lb_wdata_r <= lb_wdata;
	lb_rdata_r <= lb_rdata_x;
end
assign lb_rdata = lb_rdata_r;

// other HW I/O
(* magic_cdc *) reg status_modulator_r=0;
always @(posedge clk) status_modulator_r <= status_modulator;

// Interlock interface
(* magic_cdc *) reg dds_reset_r=0;
(* magic_cdc *) reg signed [DWLO-1:0] dds_cos_r=0;
(* magic_cdc *) reg signed [DWLO-1:0] dds_sin_r=0;
(* magic_cdc *) reg dsp_dac_pll_locked_r=0;
(* magic_cdc *) reg signed [DW-1:0] kly_rev_in_r=0;
(* magic_cdc *) reg signed [DW-1:0] beam_vol_in_r=0;
(* magic_cdc *) reg signed [DW-1:0] beam_cur_in_r=0;

always @(posedge clk) begin
    dds_reset_r <= dds_reset;
    dds_cos_r <= dds_cos;
    dds_sin_r <= dds_sin;
    dsp_dac_pll_locked_r <= dsp_dac_pll_locked;
    kly_rev_in_r <= kly_rev_in;
    beam_vol_in_r <= beam_vol_in;
    beam_cur_in_r <= beam_cur_in;
end


interlock_wrapper intlk_w (
    .clk                (clk),

    .lb_clk             (lb_clk),
    .lb_addr            (lb_addr_r),
    .lb_write           (lb_write_r),
    .lb_read            (lb_read_r),
    .lb_rvalid          (lb_rvalid_r),
    .lb_wdata           (lb_wdata_r),
    .lb_rdata           (lb_rdata_x),

    .mod_permit_out     (mod_permit_out),
    .status_modulator   (status_modulator_r),

    .dds_reset          (dds_reset_r),
    .dds_cos            (dds_cos_r),
    .dds_sin            (dds_sin_r),
    .dsp_dac_pll_locked (dsp_dac_pll_locked_r),
    .kly_rev_in         (kly_rev_in_r),
    .beam_vol_in        (beam_vol_in_r),
    .beam_cur_in        (beam_cur_in_r),

    .intlk_fault        (intlk_fault),
    .intlk_latch        (intlk_latch),
    .intlk_firstf       (intlk_firstf),
    .intlk_trig         (intlk_trig)
);

endmodule
