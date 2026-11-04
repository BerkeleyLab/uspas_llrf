`define LB_DECODE_interlock_wrapper
`include "interlock_wrapper_auto.vh"
`include "settings.vams"
// ------------------------------------
// Interlock monitoring wrapper
// ------------------------------------
module interlock_wrapper #(
    parameter integer WRONG_LB_CLK = 0,
    parameter integer NI = 8,
    parameter integer LB_DW = 32,
    parameter integer LB_ADW = 18,
    parameter integer DW = 16,
    parameter integer DWLO = 18,
    parameter integer DIVIDE_WIDTH = 26
) (
    input                clk,
    // ---------------------
    // Localbus interface
    // ---------------------
    input                lb_clk,
    input  [LB_ADW-1:0]  lb_addr,
    input                lb_write,
    input                lb_read,
    input                lb_rvalid,
    input  [31:0]        lb_wdata,
    output [31:0]        lb_rdata,
    input                lb_prefill,

    // ---------------------
    // other HW I/O
    // ---------------------
    output               mod_permit_out,
    input                status_modulator,
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

//////////////////////////////////////////////////////////
// register
//////////////////////////////////////////////////////////
wire [31:0] lb_data = lb_wdata; // for newad.py

// newad-force lb1 domain
// reg [16:0] kr_amp_thr; top-level
// reg [0:0] kr_amp_max_rst; top-level single-cycle
// reg [14:0] beam_vol_thr; top-level
// reg [0:0] beam_vol_max_rst; top-level single-cycle
// reg [14:0] beam_cur_thr; top-level
// reg [0:0] beam_cur_max_rst; top-level single-cycle
// reg [7:0] intlk_trig_cnt_res; top-level single-cycle
// reg [0:0] test_clock_ok; top-level
// reg [0:0] test_lo_fault_r; top-level
// reg [0:0] test_epics_wdog_ok; top-level
// reg [0:0] test_admin_wdog_ok; top-level
// reg [0:0] mod_permit; top-level
// newad-force lb domain

// Transfer local bus to dsp clk domain:
 wire lb1_clk = clk;
 wire [LB_DW-1:0] lb1_data;
 wire [LB_ADW-1:0] lb1_addr;
 wire lb1_write;

 data_xdomain #(.size(LB_ADW+LB_DW)) lb_to_1x(
     .clk_in(lb_clk), .gate_in(lb_write), .data_in({lb_addr,lb_data}),
     .clk_out(lb1_clk), .gate_out(lb1_write), .data_out({lb1_addr,lb1_data})
 );

`AUTOMATIC_decode

// Deep newad magic
//`AUTOMATIC_decode

//////////////////////////////////////////////////////////
// imported interlocks from LCLS-II for CLOCK_OK
// TBD
//////////////////////////////////////////////////////////
// MMCM status tracking, should detect if we ever lost clocks since setting up
// status = 0   on reset
// status = 1   set up, frozen
// status = 2   verified with PRNG
// reg [1:0] clk_status_r=0;
// reg dsp_dac_pll_locked_r=0;
// always @(posedge lb_clk) begin
//     dsp_dac_pll_locked_r <= dsp_dac_pll_locked;
//     if (clk_status_we) begin
//         if (lb_dout[0]) clk_status_r <= 1;
//         if (lb_dout[1] & (clk_status_r==1)) clk_status_r <= 2;
//     end
//     if (~dsp_dac_pll_locked_r) clk_status_r <= 0;
// end

// wire phase_ok_U4;
// reg clock_ok=1;
// always @(posedge lb_clk) clock_ok <= (clk_status_r==2) && phase_ok_U4;

//////////////////////////////////////////////////////////
// imported interlocks from LCLS-II for EPICs watch dog
//////////////////////////////////////////////////////////
reg [DIVIDE_WIDTH-1:0] prescale=0;
reg wdog_tick=0;
`ifdef SIMULATE
    always @(posedge lb_clk) begin
        prescale <= prescale + 1;
        wdog_tick <= &(prescale[DIVIDE_WIDTH-20:0]);  // 24 Hz
    end
`endif
`ifndef SIMULATE
    always @(posedge lb_clk) begin
        prescale <= prescale + 1;
        wdog_tick <= &(prescale[DIVIDE_WIDTH-6:0]);  // 24 Hz
    end
`endif

// EPICS time-to-live monitor
wire epics_timeout;
ttlive epics_wdog_mon // auto lb
(
    .clk        (lb_clk),
    .time_pulse (wdog_tick), // In 'lb_clk' domain
    .timeout_we (we_epics_wdog_mon_timeout),
    .time_fault (epics_timeout),
    `AUTOMATIC_epics_wdog_mon
);

// Admin time-to-live monitor
wire admin_timeout;
ttlive admin_wdog_mon // auto lb
(
    .clk        (lb_clk),
    .time_pulse (wdog_tick), // In 'lb_clk' domain
    .timeout_we (we_admin_wdog_mon_timeout),
    .time_fault (admin_timeout),
    `AUTOMATIC_admin_wdog_mon
);

// The watchdogs run on lb_clk: synchronize their faults to clk before they
// are combined with the clk-domain test_*_wdog_ok bits (plan step 9d)
wire epics_timeout_clk, admin_timeout_clk;
reg_tech_cdc epics_timeout_cdc (.I(epics_timeout), .C(clk), .O(epics_timeout_clk));
reg_tech_cdc admin_timeout_cdc (.I(admin_timeout), .C(clk), .O(admin_timeout_clk));

// Interlock controls wired by newad
// The instance name is used in constructing configuration register names;
// use something short and simple for EPICS' benefit.

//////////////////////////////////////////////////////////
// amplitude check on Klystron Reflected,
// Beam Current and Beam Voltage
//////////////////////////////////////////////////////////

// calculate the amplitude of the field
// kly_rev
wire signed [17:0] kly_rev_out;

// gain of the chain with: 6.22
//   * Washout filter
//   * Digital Downconverter
//   * Separate I&Q signals
//   * CORDIC
adc_to_amp_phs #(.KW(DWLO)) kr_amp_phs (
    .clk              (clk),
    .reset            (dds_reset),
    .field            (kly_rev_in),
    .cosa             (dds_cos),
    .sina             (dds_sin),
    .amp              (kly_rev_out)
);

wire [16:0] kly_rev_pos = (kly_rev_out < 0) ? 0 : kly_rev_out[16:0];
wire kly_rev_above_thr = (kly_rev_pos < kr_amp_thr) ? 0 : 1;

// reg kly_rev_above_thr;
// wire [17:0] kr_amp_thr_sig = $signed(kr_amp_thr);
// always @(posedge clk) begin
//     if (kly_rev_out > kr_amp_thr_sig)
//         kly_rev_above_thr = 1;
//     else
//         kly_rev_above_thr = 0;
// end

reg signed [17:0] kr_amp_max;
reg signed [17:0] kr_amp_min;
// store the max amplitude
always @(posedge clk) begin
    if (kr_amp_max_rst == 1) begin
        kr_amp_max <= 0;
        kr_amp_min <= 0;
    end else begin
        if (kly_rev_out > kr_amp_max) begin
            kr_amp_max <= kly_rev_out;
        end
        if (kly_rev_out < kr_amp_min) begin
            kr_amp_min <= kly_rev_out;
        end
    end
end

// calculate the amplitude of the field
// beam_vol
wire [14:0] beam_vol_pos = (beam_vol_in < 0) ? 0 : beam_vol_in[14:0];
wire beam_vol_above_thr = (beam_vol_pos < beam_vol_thr) ? 0 : 1;
reg signed [15:0] beam_vol_max;
reg signed [15:0] beam_vol_min;

// store the max amplitude
always @(posedge clk) begin
    if (beam_vol_max_rst == 1) begin
        beam_vol_max <= 0;
        beam_vol_min <= 0;
    end else begin
        if (beam_vol_in > beam_vol_max) begin
            beam_vol_max <= beam_vol_in;
        end
        if (beam_vol_in < beam_vol_min) begin
            beam_vol_min <= beam_vol_in;
        end
    end
end

// calculate the amplitude of the field
// beam_cur
wire [14:0] beam_cur_pos = (beam_cur_in < 0) ? 0 : beam_cur_in[14:0];
wire beam_cur_above_thr = (beam_cur_pos < beam_cur_thr) ? 0 : 1;
reg signed [15:0] beam_cur_max;
reg signed [15:0] beam_cur_min;

// store the max amplitude
always @(posedge clk) begin
    if (beam_cur_max_rst == 1) begin
        beam_cur_max <= 0;
        beam_cur_min <= 0;
    end else begin
        if (beam_cur_in > beam_cur_max) begin
            beam_cur_max <= beam_cur_in;
        end
        if (beam_cur_in < beam_cur_min) begin
            beam_cur_min <= beam_cur_in;
        end
    end
end

wire [NI-1:0] intlk_fault_lb, intlk_latch_lb, intlk_firstf_lb;
wire signed [15:0] beam_vol_max_lb, beam_cur_max_lb, beam_vol_min_lb, beam_cur_min_lb;
wire signed [17:0] kr_amp_max_lb, kr_amp_min_lb;
wire        status_modulator_lb;
data_xdomain #(.size(2*18+4*16+1+3*NI)) amp_max_xdomain (
    .clk_in   (clk), .gate_in  (1'b1),
    .data_in  ({beam_vol_max, beam_cur_max, kr_amp_max, beam_vol_min, beam_cur_min, kr_amp_min, status_modulator, intlk_fault, intlk_latch, intlk_firstf}),
    .clk_out  (lb_clk), .gate_out (),
    .data_out ({beam_vol_max_lb, beam_cur_max_lb, kr_amp_max_lb, beam_vol_min_lb, beam_cur_min_lb, kr_amp_min_lb, status_modulator_lb, intlk_fault_lb, intlk_latch_lb, intlk_firstf_lb})
);

// debouncer for status from modulator
wire status_modulator_db;
pb_debouncer #(
    .CNT_WIDTH (8)
) debouncer_stat_mod // auto lb
(
    .clk      (lb_clk),
    .PB       (status_modulator),
    .PB_state (status_modulator_db)
);

//////////////////////////////////////////////////////////
// interlock monitor instantiation
// INTLK_EN_BYP_MASK is used to set a BUILD time enable on the interlock bypass (available to read as a register)
//////////////////////////////////////////////////////////
interlock_mon #(.INTLK_EN_BYP_MASK(`INTLK_EN_BYP_MASK)) intlk // auto lb1
    (.clk               (clk),
    .lb_clk             (lb_clk),
    // Interlock inputs
    .pll_ok             (test_clock_ok),
    .epics_timeout      (~test_epics_wdog_ok | epics_timeout_clk),
    .lo_fault           (~test_lo_fault_r),
    .kr_amp_fault       (kly_rev_above_thr),
    .bov_fault          (beam_vol_above_thr),
    .boc_fault          (beam_cur_above_thr),
    .admin_timeout      (~test_admin_wdog_ok | admin_timeout_clk),
    .status_modulator   (status_modulator_db),
    // Interlock outputs
    .intlk_fault        (intlk_fault[NI-1:0]),
    .intlk_latch        (intlk_latch[NI-1:0]),
    .intlk_firstf       (intlk_firstf[NI-1:0]),
    .intlk_trig         (intlk_trig),
    `AUTOMATIC_intlk
);

reg [NI*32-1:0] intlk_trig_cnt=0;
wire [NI*32-1:0] intlk_trig_cnt_lb;

reg [NI-1:0] intlk_latch_dly;

genvar idni;
generate for (idni=0; idni<NI; idni=idni+1) begin: gidni
    // count for each interlock the number of incidents
    always @(posedge clk) begin
        intlk_latch_dly[idni] <= intlk_latch[idni];
        if ((intlk_latch[idni] == 1) & (intlk_latch_dly[idni] == 0)) begin
            intlk_trig_cnt[(idni+1)*32-1:idni*32] <= intlk_trig_cnt[(idni+1)*32-1:idni*32] + 1;
        end else begin
            if (intlk_trig_cnt_res[idni] == 1) begin
                intlk_trig_cnt[(idni+1)*32-1:idni*32] <= 0;
            end
        end
    end
end endgenerate

// ---------------------
// Read-only address space decoding
// ---------------------
// Semi-manual address decoding that's parsed by reverse_json.py
reg [LB_DW-1:0] lb_rdata_r=0;
reg [31:0] reg_bank_0=0, reg_bank_1=0;
reg [LB_ADW-1:0] lb_addr_d1=0;

reg [7:0] intlk_en_byp_int=0;
wire [31:0] pll_nlock_cnt     = intlk_trig_cnt[1*32-1:0*32];
wire [31:0] epics_timeout_cnt = intlk_trig_cnt[2*32-1:1*32];
wire [31:0] lo_fault_cnt      = intlk_trig_cnt[3*32-1:2*32];
wire [31:0] kr_amp_fault_cnt  = intlk_trig_cnt[4*32-1:3*32];
wire [31:0] bov_fault_cnt     = intlk_trig_cnt[5*32-1:4*32];
wire [31:0] boc_fault_cnt     = intlk_trig_cnt[6*32-1:5*32];
wire [31:0] admin_timeout_cnt = intlk_trig_cnt[7*32-1:6*32];
wire [31:0] mod_stat_bad_cnt  = intlk_trig_cnt[8*32-1:7*32];

always @(posedge lb_clk) intlk_en_byp_int <= `INTLK_EN_BYP_MASK;

// jit_rad == Just In Time Readout Across Domains
wire lb_error;
wire xfer_clk, xfer_strobe, xfer_snap;
wire [3:0] xfer_addr;
wire [31:0] lb_reg_bank_1;
jit_rad_gateway #(.passthrough(0)) xfer_bank_1(
    .lb_clk(lb_clk), .lb_addr(lb_addr[3:0]),
    .lb_strobe(lb_read), .lb_odata(lb_reg_bank_1),
    .lb_prefill(lb_prefill), .lb_error(lb_error),
    .app_clk(clk), .xfer_clk(xfer_clk), .xfer_strobe(xfer_strobe),
    .xfer_addr(xfer_addr), .xfer_odata(reg_bank_1), .xfer_snap(xfer_snap)
);

// leave 4k space at the begining of the page
// reverse_json_offset: 528384
always @(posedge lb_clk) if (lb_read) begin
    case (lb_addr[3:0])
        4'h0: reg_bank_0 <= intlk_en_byp_int;
        //4'h1: reg_bank_0 <= clk_status;             // alias: clk_status_out
        4'h6: reg_bank_0 <= $signed(kr_amp_min_lb);          // alias: kr_amp_min
        4'h7: reg_bank_0 <= $signed(beam_vol_min_lb);        // alias: beam_vol_min
        4'h8: reg_bank_0 <= $signed(beam_cur_min_lb);        // alias: beam_cur_min
        4'h9: reg_bank_0 <= status_modulator_lb;             // alias: status_modulator
        4'ha: reg_bank_0 <= $signed(kr_amp_max_lb);          // alias: kr_amp_max
        4'hb: reg_bank_0 <= $signed(beam_vol_max_lb);        // alias: beam_vol_max
        4'hc: reg_bank_0 <= $signed(beam_cur_max_lb);        // alias: beam_cur_max
        4'hd: reg_bank_0 <= intlk_fault_lb;         // alias: intlk_fault
        4'he: reg_bank_0 <= intlk_latch_lb;         // alias: intlk_latch
        4'hf: reg_bank_0 <= intlk_firstf_lb;        // alias: intlk_firstf
        default: reg_bank_0 <= 32'hface1234;
    endcase
    end

always @(posedge xfer_clk) begin
    case (xfer_addr[3:0])
        // All these signals are in dsp_clk domain
        // (and handled with jit_rad)
        4'h0: reg_bank_1 <= pll_nlock_cnt;
        4'h1: reg_bank_1 <= epics_timeout_cnt;
        4'h2: reg_bank_1 <= lo_fault_cnt;
        4'h3: reg_bank_1 <= kr_amp_fault_cnt;
        4'h4: reg_bank_1 <= bov_fault_cnt;
        4'h5: reg_bank_1 <= boc_fault_cnt;
        4'h6: reg_bank_1 <= admin_timeout_cnt;
        4'h7: reg_bank_1 <= mod_stat_bad_cnt;
        default: reg_bank_1 <= 32'hface5678;
    endcase
end

// lb_read: Match READ_DELAY=3 in system.v, check timing in simulation
always @(posedge lb_clk) if (lb_read) begin
    lb_addr_d1 <= lb_addr;
    casez (lb_addr_d1)
        18'h00???: lb_rdata_r <= mirror_out_0;  // automatic address map
        18'h0100?: lb_rdata_r <= reg_bank_0;
        18'h0101?: lb_rdata_r <= lb_reg_bank_1;
        default:   lb_rdata_r <= 32'hdeadface;
    endcase
end

assign lb_rdata = lb_rdata_r;
assign mod_permit_out = mod_permit;

endmodule
