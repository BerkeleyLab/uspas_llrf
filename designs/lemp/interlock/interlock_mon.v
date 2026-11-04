`timescale 1ns / 1ns

// ------------------------------------
// Interlock monitoring
//
// All intlk_foo registers are built with
//   bit 0:  Internal PLL lock fault
//   bit 1:  EPICS timeout
//   bit 2:  Local oscillator out-of-range fault
//   bit 3:  Klystron reverse amplitude
//   bit 4:  Beam over-voltage
//   bit 5:  Beam over-current
//   bit 6:  Admin timeout (NOT YET USED)
//   bit 7:  Modulator status fault
//
//   INTLK_EN_BYP_MASK is used to set a BUILD time enable on the interlock bypass
//
// Host inputs wired through newad
//
// Single-clock-domain logic,
// all inputs _must_ be qualified in that domain.
// Well, that rule can have an exception if WRONG_LB_CLK parameter is set.
// That creates an workaround needed for the newad context.  See
// https://gitlab.lbl.gov/hdl-libraries/bedrock/-/wikis/Newad-upgrade-proposal
// for ideas about an actual long-term fix.
//
// ==========================================================================================
// === NOTE: Changes here must be reflected in uspas_llrf/python/interlocks/interlocks.py ===
// ==========================================================================================

module interlock_mon #(
   parameter integer WRONG_LB_CLK = 0,
   parameter integer NI = 8,
   parameter [7:0]   INTLK_EN_BYP_MASK = 32'hFF  // this mask is used to enable bypass on the specific interlocks
) (
   input clk,
   input lb_clk,

   // Interlock controls
   input [7:0] intlk_byp,  // external
   input [7:0] intlk_reset,  // external single-cycle

   // Interlock inputs (must have 'NI' number of input ports here)
   input pll_ok,
   input epics_timeout,
   input lo_fault,
   input kr_amp_fault,
   input bov_fault,
   input boc_fault,
   input admin_timeout,
   input status_modulator,

   // Interlock outputs
   output [NI-1:0] intlk_fault,   // Current fault when '1'
   output [NI-1:0] intlk_latch,   // Latched fault when '1'
   output [NI-1:0] intlk_firstf,  // First fault indication
   output          intlk_trig     // Single-cycle start-of-fault indicator
);
   // fake enum (make sure to not clobber numbers here!!!)
   localparam PLL_NLOCK    = 0;
   localparam EPICS_TOUT   = 1;
   localparam LO_FAULT     = 2;
   localparam KR_FAULT     = 3;
   localparam BOV_FAULT    = 4;
   localparam BOC_FAULT    = 5;
   localparam ADMIN_TOUT   = 6;
   localparam MOD_STAT_BAD = 7;
   // Highest number should be NI-1

   wire [NI-1:0] intlk_fault_l, intlk_fault_masked;
   assign intlk_fault_l[PLL_NLOCK]    = ~pll_ok;
   assign intlk_fault_l[EPICS_TOUT]   = epics_timeout;
   assign intlk_fault_l[LO_FAULT]     = lo_fault;
   assign intlk_fault_l[KR_FAULT]     = kr_amp_fault;
   assign intlk_fault_l[BOV_FAULT]    = bov_fault;
   assign intlk_fault_l[BOC_FAULT]    = boc_fault;
   assign intlk_fault_l[ADMIN_TOUT]   = admin_timeout;
   assign intlk_fault_l[MOD_STAT_BAD] = status_modulator;

   (* ASYNC_REG = "TRUE" *) reg [NI-1:0] intlk_fault_lr=0;  // allow non-single-cycle inputs from other domains
   always @(posedge clk) intlk_fault_lr <= intlk_fault_l;

   // ====== Nothing below here needs to be modified to add an interlock ======
   // ======            (unless you're doing something weird)            ======

   // Move intlk_byp and intlk_reset signals to the right domain, if needed.
   // Wish I didn't have to do this.  If used,
   // it will increase hardware footprint by about 30 LUT per instance.
   wire [NI-1:0] byp_r, reset_r;
   generate if (WRONG_LB_CLK) begin: stupid
      flag_xdomain fx[NI-1:0](.clk1(lb_clk), .flagin_clk1(intlk_reset), .clk2(clk), .flagout_clk2(reset_r));
      reg [NI-1:0] byp_rr=0; always @(posedge clk) byp_rr <= intlk_byp ;
      assign byp_r = byp_rr;
   end else begin: clean
      assign byp_r = intlk_byp;
      assign reset_r = intlk_reset;
   end endgenerate

   reg  [NI-1:0] intlk_mask;
   reg  [NI-1:0] intlk_latch_l=0, intlk_firstf_l=0;

   assign intlk_fault_masked = intlk_fault_lr & intlk_mask;

   // use the parameter to mask the interlock
   always @(byp_r) begin
       intlk_mask = ~byp_r | ~INTLK_EN_BYP_MASK[NI-1:0];
       // intlk_mask[PLL_NLOCK] = 1;  // can't mask clock fault
   end

   always @(posedge clk) begin
      intlk_latch_l <= (intlk_latch_l & ~reset_r) | intlk_fault_masked;

      // Latch faults as we first go from non-fault to fault
      if (intlk_latch_l==0 && intlk_fault_masked!=0)
         intlk_firstf_l <= intlk_fault_masked;
      else
         intlk_firstf_l <= intlk_firstf_l & ~reset_r;
   end

   // Create single-cycle event when interlocks fire
   reg intlk_summary=0, intlk_trig_l=0;
   wire intlk_latch_any = |intlk_latch_l;
   always @(posedge clk) begin
      intlk_summary <= intlk_latch_any;
      intlk_trig_l <= intlk_latch_any & ~intlk_summary;  // rising edge detect
   end

   assign intlk_fault  = intlk_fault_lr;
   assign intlk_latch  = intlk_latch_l;
   assign intlk_firstf = intlk_firstf_l;
   assign intlk_trig   = intlk_trig_l;

endmodule
