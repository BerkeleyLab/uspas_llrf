// LEMP top-level IO and interlock, included at the end of marble_zest_mid.vh.
// Enabled by the DESIGN_* defines in top/lemp/Makefile. From the LEMP
// branch (2e25cd9) top/marble_zest, plan step 9e.

// ----------------------------------
// interlock_wrapper, @ lb_base_2 (designs/lemp/interlock, newad, D23)
// ----------------------------------
wire        mod_permit_out;
wire        status_modulator_in;
wire        dsp_dac_pll_locked = 1'b1;
wire signed [15:0] kly_rev_in  = adc_out_data[3*16-1:2*16];  // ADC2  J6  Kly REV
wire signed [15:0] beam_vol_in = adc_out_data[7*16-1:6*16];  // ADC6 J10 Beam Voltage
wire signed [15:0] beam_cur_in = adc_out_data[8*16-1:7*16];  // ADC7 J11 Beam Current
wire [7:0]  intlk_fault;
wire [7:0]  intlk_firstf;
wire        intlk_trig;

interlock_wrapper intlk_w_inst (
    .clk                (dsp_clk),

    .lb_clk             (lb_clk),
    .lb_addr            (lb_addr[17:0]),
    .lb_write           (lb_write_2),
    .lb_read            (lb_read_2),
    .lb_wdata           (lb_wdata),
    .lb_rdata           (lb_rdata_2),
    .lb_rvalid          (lb_rvalid),
    .lb_prefill         (1'b0),  // unconnected on the LEMP branch

    .mod_permit_out     (mod_permit_out),
    .status_modulator   (status_modulator_in),

    .dds_reset          (dds_reset),
    .dds_cos            (dds_cos),
    .dds_sin            (dds_sin),

    .dsp_dac_pll_locked (dsp_dac_pll_locked),
    .kly_rev_in         (kly_rev_in),
    .beam_vol_in        (beam_vol_in),
    .beam_cur_in        (beam_cur_in),

    .intlk_fault        (intlk_fault),
    .intlk_latch        (intlk_latch),
    .intlk_firstf       (intlk_firstf),
    .intlk_trig         (intlk_trig)
);

// ----------------------------------
// PMOD1/2, ZEST_PMOD1/2, ZEST_HDMI assignments
// ----------------------------------
// PMOD1        <=====> Rear I/O board
// PMOD1_0      <------ Test fiducial (not used: the shell has no fiducial input)
// PMOD1_1      ------> Permit to LLRF relay
// PMOD1_2      ------>
// PMOD1_3      <------ Status from Modulator
// PMOD1_4      ------> mod_trig & mod_permit_out
// PMOD1_5      ------> SSSB trigger
// PMOD1_6      ------> Scope trigger
// PMOD1_7      ------> Spare trigger

// PMOD2        ======> {evr_events, pmod_trigs}, for diagnostics

// ZEST_PMOD1   <=====> SSSB controls
// ZEST_PMOD1_2 <------ Alarm     (Terminal 1)
// ZEST_PMOD1_3 ------> RF switch (Terminal 3 - active low)
// ZEST_PMOD1_6 ------> Reset     (Terminal 4 - active low)
// ZEST_PMOD1_7 <------ RF Status (Terminal 6 - ON=Hi OFF=low)

// ZEST_PMOD2   <=====> 5-LED board (not driven)

// ZEST_HDMI      <=====> Rear I/O board
// ZEST_HDMI_SCL  ------> Permit to LLRF relay
// ZEST_HDMI_CEC  <------ Status from Modulator
// ZEST_HDMI_D1_P ------> mod_trig & mod_permit_out (fiber, inverted)
// ZEST_HDMI_D1_N /
// ZEST_HDMI_CK_P ------> mod_trig & mod_permit_out (copper)
// ZEST_HDMI_CK_N /
// ZEST_HDMI_D0_P ------> SSSB trigger (inverted)
// ZEST_HDMI_D0_N /
// ZEST_HDMI_D2_P ------> Scope trigger (inverted)
// ZEST_HDMI_D2_N /

// LLRF INTERLOCKS RELAY OUT control by interlock latched register
// 0 = OK, 1 = fault
assign PMOD1[1] = (|intlk_latch[6:0]);
// HDMI_SCL follows relay control (push-pull)
assign ZEST_HDMI_SCL = (|intlk_latch[6:0]);

// STATUS FROM MODULATOR IN - PMOD
reg status_modulator_in_pmod = 0;
always @(posedge dsp_clk) begin
    status_modulator_in_pmod <= PMOD1[3];
end

// STATUS FROM MODULATOR IN - HDMI
reg [1:0] mod_status_rb_cec_sync = 2'b00;
reg       status_modulator_in_hdmi = 1'b0;
always @(posedge dsp_clk) begin
    mod_status_rb_cec_sync   <= {mod_status_rb_cec_sync[0], ZEST_HDMI_CEC};
    status_modulator_in_hdmi <= mod_status_rb_cec_sync[1];
end

// GENERAL STATUS FROM MODULATOR IN
assign status_modulator_in = status_modulator_in_pmod & status_modulator_in_hdmi;

// PULSE GEN 0 (MOD TRIGGER)
assign PMOD1[4] = pmod_trigs[0] & mod_permit_out;

// PULSE GEN 1 (SSSB GATE)
// PULSE GEN 2 (SCOPE TTL)
// PULSE GEN 3 (EXTRA)
assign PMOD1[7:5] = pmod_trigs[3:1];

assign PMOD2 = {evr_events, pmod_trigs};

// ZEST_PMOD1 - SSSB controls
assign ZEST_PMOD1[3] = sssb_rf_switch;
assign ZEST_PMOD1[6] = sssb_rst;
always @(posedge dsp_clk) begin
    sssb_alarm <= ZEST_PMOD1[2];
    sssb_rf_status <= ZEST_PMOD1[7];
end

// The HDMI pairs stay inout ports of marble_zest_top.v; these OBUFDS make
// them fixed LVDS outputs (no tristate buffer, as on the LEMP branch)
`ifndef SIMULATE
OBUFDS #(
    .IOSTANDARD("LVDS_25")  // LVDS 2.5V standard
) obufds_inst_d0 (
    .I  (~pmod_trigs[1]),  // SSSB Gate
    .O  (ZEST_HDMI_D0_P),
    .OB (ZEST_HDMI_D0_N)
);

OBUFDS #(
    .IOSTANDARD("LVDS_25")
) obufds_inst_d1 (
    .I  (~pmod_trigs[0] & mod_permit_out),  // Mod Trigger, fiber
    .O  (ZEST_HDMI_D1_P),
    .OB (ZEST_HDMI_D1_N)
);

OBUFDS #(
    .IOSTANDARD("LVDS_25")
) obufds_inst_d2 (
    .I  (~pmod_trigs[2]),  // Ext TTL Trigger
    .O  (ZEST_HDMI_D2_P),
    .OB (ZEST_HDMI_D2_N)
);

OBUFDS #(
    .IOSTANDARD("LVDS_25")
) obufds_inst_d3 (
    .I  (pmod_trigs[0] & mod_permit_out),  // MOD trigger, copper
    .O  (ZEST_HDMI_CK_P),
    .OB (ZEST_HDMI_CK_N)
);
`endif
