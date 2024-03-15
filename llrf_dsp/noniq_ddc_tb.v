`timescale 1ns / 1ns
`include "constants.vams"
`include "settings.vams"

module noniq_ddc_tb;
parameter N = 100;                  // n-th sample from ADC
parameter FDOWN_WAIT = 11;          // fdownconvert latency, in clock cycles
parameter N1 = 113;                 // time to change input phase

parameter real AMP_ACCURACY = 0.001;// < 0.1% RMS
parameter real PHS_ACCURACY = 0.1;  // < 0.1 deg RMS

reg clk, trace=0;
integer cc;
integer out_file;
reg pass=1;
initial begin
    $display("##################################################");
    $display("    ---- Checking noniq_ddc.v ----");
    if ($test$plusargs("vcd")) begin
        $dumpfile("noniq_ddc.vcd");
        $dumpvars(5,noniq_ddc_tb);
    end

    for (cc=0; cc<N+25; cc=cc+1) begin
        clk=0; #5;
        clk=1; #5;
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

real ampi = 10000;         // full scale: 2^15
real phsi = 30;            // deg
real theta;
reg signed [15:0] a_data=16'hxxxx;
always @(posedge clk) begin
    theta <= cc * `M_TWO_PI * `NUM_DDS / `DEN_DDS - phsi * `M_PI / 180;
    if (cc >= N ) a_data <= $floor(ampi * $cos(theta));
    if (cc == N1) phsi = 45;    // deg
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

wire i_sel;
wire signed [16:0] field_iq;
noniq_ddc #(.ODW(17)) dut(
    .clk        (clk),
    .cosd       (cosd),
    .sind       (sind),
    .a_data     (a_data),
    .i_sel      (i_sel),
    .o_data     (field_iq)
);

wire signed [17:0] field_i, field_q;
// Interpolate downconverted field signals to get separate I&Q signals
fiq_interp #(.a_dw(17), .i_dw(18), .q_dw(18)) interp(
    .clk    (clk),
    .a_data (field_iq),
    .a_gate (1'b1),
    .a_trig (i_sel),
    .i_data (field_i),
    .q_data (field_q)
);

// Validation
// | I | = gain * |  sin[n + 1]\theta   -sin n\theta |  X  | a_data[n]   |
// | Q |          | -cos[n + 1]\theta    cos n\theta |     | a_data[n+1] |
//
// import numpy as np
// pi = np.pi
// def calc_iq(n, adc):
//     theta = 4 / 11
//     gain = 1 / np.sin(2*pi*theta)
//     i = gain * (np.sin(theta * n * 2*pi) * adc[0] - np.sin(theta * (n-1) * 2*pi) * adc[1])
//     q = gain * (-np.cos(theta * n * 2*pi) * adc[0] + np.cos(theta * (n-1) * 2*pi) * adc[1])
//     return i, q
// adc = 10000 * np.cos([-pi/6, -pi/6 + 2*pi*4/11])  # [8660, -1893]
// calc_iq(100, adc)
// (8659.999999999947, 4999.1347453875105)

real gain = 1 / $sin(`M_TWO_PI * `NUM_DDS / `DEN_DDS);
real expect_num_i, expect_num_q;
reg signed [15:0] a_data_pre=0;

always @(posedge clk) begin
    a_data_pre <= a_data;
    # 1;
    expect_num_i <= gain * (
        $sin((cc-1) * `M_TWO_PI * `NUM_DDS / `DEN_DDS) * a_data_pre -
        $sin((cc-2) * `M_TWO_PI * `NUM_DDS / `DEN_DDS) * a_data);
    expect_num_q <= gain * (
       -$cos((cc-1) * `M_TWO_PI * `NUM_DDS / `DEN_DDS) * a_data_pre +
        $cos((cc-2) * `M_TWO_PI * `NUM_DDS / `DEN_DDS) * a_data);
end

real expect_i, expect_q;
real amp_meas, phs_meas;
always @(posedge clk) begin
    # 1;
    expect_i = ampi * $cos(phsi * `M_PI / 180);
    expect_q = ampi * $sin(phsi * `M_PI / 180);
    amp_meas = $hypot(field_i, field_q) / `DDC_AMP_GAIN;
    phs_meas = $atan2(field_q, field_i) * 180 / `M_PI - `DDC_PHS_GAIN;
    if (cc == N + FDOWN_WAIT || cc == N1 + FDOWN_WAIT) begin
        $display("cc = %4d:", cc);
        $display("  Mathematical Expect: I: %8.1f, Q: %8.1f, Amp = %8.1f, Phs = %6.1f deg",
            expect_i, expect_q, ampi, phsi);
        pass &= $abs((expect_num_i - expect_i) / expect_i) < AMP_ACCURACY;
        pass &= $abs((expect_num_q - expect_q) / expect_q) < AMP_ACCURACY;
        $display("  Numerical    Expect: I: %8.1f, Q: %8.1f, Amp = %8.1f, Phs = %6.1f deg, %s",
            expect_num_i, expect_num_q,
            $hypot(expect_num_i, expect_num_q),
            $atan2(expect_num_q, expect_num_i) * 180 / `M_PI,  pass ? "PASS" : "FAIL");
        pass &= $abs((amp_meas - ampi) / ampi) < AMP_ACCURACY;
        pass &= $abs((phs_meas - phsi + 180) % 360 - 180) < PHS_ACCURACY;
        $display("  Measured     Result: I: %8d, Q: %8d, Amp = %8.1f, Phs = %6.1f deg, %s",
            field_i, field_q, amp_meas, phs_meas, pass ? "PASS" : "FAIL");
    end
end

endmodule
