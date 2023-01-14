`timescale 1ns / 1ps
`include "constants.vams"
`include "settings.vams"

module dsp_core_tb;

parameter real AMP_ACCURACY = 0.003;    // From spec, p2p, XXX should be 0.1%   RMS
parameter real PHS_ACCURACY = 0.2;      // From spec, p2p, XXX should be 0.1deg RMS

parameter FDOWN_WAIT        = 11;       // fdownconvert latency, in clock cycles
parameter NO_DC_WAIT        = 70;       // settling time of washout filter, in clock cycles
parameter CORDIC_STAGES     = 20;       // cordic stages, in clock cycles

localparam integer SETTLE_TIME = FDOWN_WAIT + NO_DC_WAIT + CORDIC_STAGES;

// three stages: RX, then open loop, then close loop
parameter N_RX                = 100;      // RX test time
localparam integer N_LOOPBACK = N_RX + SETTLE_TIME + 200;
localparam integer N_FEEDBACK = N_LOOPBACK + SETTLE_TIME + 200;
localparam integer N_CHECK = N_FEEDBACK + 3500;

parameter real RX_AMP_GAIN  = `RX_AMP_GAIN * `CORDIC_GAIN;    // Measured
parameter real RX_PHS_GAIN  = 0;        // Measured, deg
parameter real OPEN_AMP_GAIN = 2**19 / (`CORDIC_GAIN * `LO_AMP * `CORDIC_GAIN);
parameter real OPEN_PHS_GAIN = 0;       // Measured, deg

parameter integer AMP_SETP = 10000;     // full scale: 2^17
parameter integer PHS_SETP = -180;       // deg

localparam real ampi = AMP_SETP;        // full scale: 2^15
localparam real phsi = PHS_SETP;        // deg

reg clk=0, trace=0;
integer cc=0;

reg pass=1;
initial begin
    $display("##################################################");
    $display("    ---- Checking dsp_core.v ----");
    if ($test$plusargs("vcd")) begin
        $dumpfile("dsp_core.vcd");
        $dumpvars(5,dsp_core_tb);
    end

    for (cc=0; cc<=N_CHECK+2; cc=cc+1) begin
        clk=0; #(`DSP_CLK_CYCLE/2);
        clk=1; #(`DSP_CLK_CYCLE/2);
    end
    $display("Validation: %s.", pass ? "PASS":"FAIL");
    $display("##################################################");
    if (pass) $finish();
    else $stop();
end

`include "settings.vh"
reg [19:0] phase_step_h;
reg [11:0] phase_step_l;
reg [11:0] modulo;

initial begin
    init_dds_task(phase_step_h, phase_step_l, modulo);
end

integer ADC_DC_CNT = 500;// DC part as a test of no-dc filter

real theta;
reg signed [15:0] adc_data=16'hxxxx;
always @(posedge clk) begin
    theta <= cc * `M_TWO_PI * `NUM_DDS / `DEN_DDS - phsi * `M_PI / 180;
    if (cc >= N_RX ) adc_data <= $floor(ampi * $cos(theta)) + ADC_DC_CNT;
end

wire signed [17:0] cosd, sind;
wire [18:0] dds_phase_acc;
ph_acc dds_lo_i (
    .clk            (clk),
    .reset          (1'b0),
    .en             (1'b1),
    .phase_acc      (dds_phase_acc),
    .phase_step_h   (phase_step_h),
    .phase_step_l   (phase_step_l),
    .modulo         (modulo)
);

cordicg_b22 #(.nstg(20), .width(18)) dds_cordicg_i(
    .clk            (clk),
    .opin           (2'b00),
    .xin            (18'd`LO_AMP),
    .yin            (18'd0),
    .phasein        (dds_phase_acc + `N_PHASE_SHIFT),
    .xout           (cosd),
    .yout           (sind)
);

parameter KW=18;
parameter EW=15;
reg signed [17:0] amp_setpoint = 0;
reg signed [17:0] phs_setpoint = 0;
reg signed [17:0] Kp_amp = 8000;
reg signed [17:0] Kp_phs = 8000;
reg signed [17:0] Ki_amp = 400;
reg signed [17:0] Ki_phs = 400;

reg reset=0;
reg loop_back=0;
reg check_valid=0;
reg amp_loop_enable=0;
reg phs_loop_enable=0;
reg amp_loop_reset=0;
reg phs_loop_reset=0;
wire signed [15:0] dac_out;
wire [15:0] cav_field = loop_back ? dac_out + ADC_DC_CNT : adc_data;
wire signed [EW-1:0] err_out_amp;
wire signed [EW-1:0] err_out_phs;
dsp_core #(.KW(KW), .EW(EW)) dut(
    .clk            (clk),
    .reset          (reset),
    .cav_field      (cav_field),
    .cosa           (cosd),
    .sina           (sind),
    .dac_out        (dac_out),
    .amp_setpoint   (amp_setpoint),
    .phs_setpoint   (phs_setpoint),
    .Kp_amp         (Kp_amp),
    .Kp_phs         (Kp_phs),
    .Ki_amp         (Ki_amp),
    .Ki_phs         (Ki_phs),
    .amp_loop_enable(amp_loop_enable),
    .phs_loop_enable(phs_loop_enable),
    .amp_loop_reset (amp_loop_reset),
    .phs_loop_reset (phs_loop_reset),
    .err_out_amp    (err_out_amp),
    .err_out_phs    (err_out_phs)
);

initial begin
    amp_setpoint = AMP_SETP * OPEN_AMP_GAIN;
    phs_setpoint = (PHS_SETP + OPEN_PHS_GAIN) / 360 * 2**18;
    @ (cc == N_RX);
    $display("cc = %4d, ###### RX testing...       ######", cc);
    reset = 1;
    @ (cc == N_RX+1);
    reset = 0;
    @ (cc == N_RX + SETTLE_TIME);
    check_valid = 1;
    @ (cc == N_LOOPBACK);
    $display("cc = %4d, ###### OpenLoop testing... ######", cc);
    loop_back = 1;
    check_valid = 0;
    @ (cc == N_LOOPBACK + SETTLE_TIME);
    check_valid = 1;
    @ (cc == N_FEEDBACK);
    $display("cc = %4d, ###### CloseLoop testing...######", cc);
    check_valid = 0;
    @(posedge clk) amp_loop_reset = 1;
    @(posedge clk) phs_loop_reset = 1;
    amp_setpoint = AMP_SETP * RX_AMP_GAIN;
    phs_setpoint = (PHS_SETP + RX_PHS_GAIN) / 360 * 2**18;
    @(posedge clk) amp_loop_enable = 1;
    @(posedge clk) amp_loop_reset = 0;
    @(posedge clk) phs_loop_enable = 1;
    @(posedge clk) phs_loop_reset = 0;
    @ (cc == N_CHECK);
    check_valid = 1;
end


real expect_i, expect_q;
real amp_out, phs_out;

always @(posedge clk) begin
    # 1;
    expect_i = ampi * $cos(phsi * `M_PI / 180);
    expect_q = ampi * $sin(phsi * `M_PI / 180);
    amp_out = dut.amp_measured / RX_AMP_GAIN;
    phs_out = dut.phs_measured * 360.0 / 2**18 - RX_PHS_GAIN; // deg
    if (phs_out < -180) phs_out += 360;
    else if (phs_out >= 180) phs_out -= 360;

    if (check_valid) begin
        pass &= $abs((amp_out - ampi) / ampi) < AMP_ACCURACY;
        // wrap phase error
        pass &= $abs((phs_out - phsi + 180) % 360 - 180 ) < PHS_ACCURACY;
    end
    if (cc == (N_RX + SETTLE_TIME) ||
        cc == (N_LOOPBACK + SETTLE_TIME) ||
        cc == (N_CHECK) ||
        !pass) begin
        $display("cc = %4d:", cc);
        $display("  Mathematical Expect: I: %8.1f, Q: %8.1f, Amp = %8.1f cnt, Phs = %8.2f deg",
            expect_i, expect_q, ampi, phsi);
        $display("  Measured     Result: A: %8d, P: %8d, Amp = %8.1f cnt, Phs = %8.2f deg",
            dut.amp_measured, dut.phs_measured, amp_out, phs_out);
        // $display("  Drive: I: %8.1f, Q: %8.1f, Amp = %8.1f cnt, Phs = %8.2f deg",
        //     dut.drive_i, dut.drive_q, $hypot(dut.drive_i, dut.drive_q),
        //     $atan2(dut.drive_q, dut.drive_i) * 180 / `M_PI);
        if (!pass) $stop();
    end
end

endmodule
