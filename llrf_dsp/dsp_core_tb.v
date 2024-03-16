`timescale 1ns / 1ps
`include "constants.vams"
`include "settings.vams"

module dsp_core_tb;

parameter real AMP_ACCURACY = 0.001;      // From spec, p2p %0.1
parameter real PHS_ACCURACY = 0.1;        // From spec, p2p 0.1 deg

parameter integer FDOWN_WAIT    = 11;     // fdownconvert latency, in clock cycles
parameter integer NO_DC_WAIT    = 70;     // settling time of washout filter, in clock cycles
parameter integer CORDIC_STAGES = 20;     // cordic stages, in clock cycles

localparam integer SETTLE_TIME = 2*(FDOWN_WAIT + NO_DC_WAIT + CORDIC_STAGES);

// three stages of testing: RX; open loop; close loop
parameter integer  N_RX       = 100;      // RX test time
localparam integer N_LOOPBACK = N_RX + SETTLE_TIME + 200;
localparam integer N_FEEDBACK = N_LOOPBACK + SETTLE_TIME + 200;
localparam integer N_CHECK    = N_FEEDBACK + 7000;

parameter integer ADC_DC_CNT  = 500;     // DC part as a test of no-dc filter
parameter integer AMP_SETP_ADC= 10000;   // full scale: 2^17
parameter integer PHS_SETP_DEG= 20;      // deg

parameter integer KW=18;
parameter integer EW=15;

real ampi = AMP_SETP_ADC;        // full scale: 2^15
real phsi = PHS_SETP_DEG;

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

reg signed [17:0] amp_setpoint;
reg signed [17:0] phs_setpoint;
reg signed [17:0] amp_setpoint_close;
reg signed [17:0] phs_setpoint_close;
real open_amp_gain;
real open_phs_gain;
initial begin
    init_dds_task(phase_step_h, phase_step_l, modulo);
    calc_loop_gain_task(
        AMP_SETP_ADC, PHS_SETP_DEG,
        open_amp_gain, open_phs_gain,
        amp_setpoint, phs_setpoint,
        amp_setpoint_close, phs_setpoint_close);
end

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
    .phasein        (dds_phase_acc),
    .xout           (cosd),
    .yout           (sind)
);


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
    #1;
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
    amp_setpoint = amp_setpoint_close;
    phs_setpoint = phs_setpoint_close;
    @(posedge clk) amp_loop_enable = 1;
    @(posedge clk) amp_loop_reset = 0;
    @(posedge clk) phs_loop_enable = 1;
    @(posedge clk) phs_loop_reset = 0;
    @ (cc == N_CHECK);
    check_valid = 1;
end

real expect_i, expect_q;
real amp_meas, phs_meas;
real amp_drive, phs_drive;
reg pass_rx=1, pass_tx=1;
real tx_lo_phs = $signed(`TX_LO_PHS);

always @(posedge clk) begin
    # 1;
    expect_i = ampi * $cos(phsi * `M_PI / 180);
    expect_q = ampi * $sin(phsi * `M_PI / 180);
    amp_meas = dut.amp_measured / `AMP_SETP_GAIN;
    phs_meas = dut.phs_measured * 360.0 / 2**18; // deg
    amp_drive = $hypot(dut.drive_i, dut.drive_q) / (2**19 / (`CORDIC_GAIN * `LO_AMP));
    phs_drive = $atan2(dut.drive_q, dut.drive_i) * 180 / `M_PI - (tx_lo_phs / (1 << 19)) * 360;
    if (phs_meas < -180) phs_meas += 360;
    else if (phs_meas >= 180) phs_meas -= 360;

    if (check_valid) begin
        pass_rx &= $abs((amp_meas - ampi) / ampi) < AMP_ACCURACY;
        pass_rx &= $abs((phs_meas - phsi + 180) % 360 - 180 ) < PHS_ACCURACY;
        pass_tx &= $abs((amp_drive - ampi) / ampi) < AMP_ACCURACY;
        pass_tx &= $abs((phs_drive - phsi + 180) % 360 - 180 ) < PHS_ACCURACY;
        pass &= pass_rx & pass_tx;
        // if (!pass) $stop();
    end
    // if (check_valid) begin
    if (cc == (N_RX + SETTLE_TIME) ||
        cc == (N_LOOPBACK + SETTLE_TIME) ||
        cc == (N_CHECK) ||
        !pass) begin
        $display("cc = %4d:", cc);
        $display("  TX Drive   : I: %8d, Q: %8d, Amp = %8.1f cnt, Phs = %6.2f deg, %s",
            dut.drive_i, dut.drive_q,
            amp_drive, phs_drive,
            pass_tx ? "PASS" : "FAIL");
        $display("  RX Expect  : I: %8.1f, Q: %8.1f, Amp = %8.1f cnt, Phs = %6.2f deg",
            expect_i, expect_q, ampi, phsi);
        $display("  RX Measured: A: %8d, P: %8d, Amp = %8.1f cnt, Phs = %6.2f deg, %s",
            dut.amp_measured, dut.phs_measured,
            amp_meas, phs_meas,
            pass_rx ? "PASS" : "FAIL");

        if (!pass) $stop();
    end
end

endmodule
