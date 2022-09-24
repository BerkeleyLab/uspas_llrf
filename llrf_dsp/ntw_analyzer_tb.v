`timescale 1ns / 1ps
`include "constants.vams"
`include "settings.vams"

module ntw_analyzer_tb;
parameter N = 50000;

reg clk, trace=0, pass=1;
integer cc=0;
integer out_file;
initial begin
    $display("##################################################");
    $display("    ---- Checking ntw_analyzer.v ----");
    if ($test$plusargs("vcd")) begin
        $dumpfile("ntw_analyzer.vcd");
        $dumpvars(7, ntw_analyzer_tb);
    end
    if ($test$plusargs("trace")) begin
        trace = 1;
        out_file = $fopen("ntw_analyzer.dat", "w");
    end
    for (cc=0; cc < N; cc=cc+1) begin
        clk=0; #(`DSP_CLK_CYCLE/2);
        clk=1; #(`DSP_CLK_CYCLE/2);
    end
    $display("Validation: %s.", pass ? "PASS":"FAIL");
    $display("##################################################");
    if (pass) $finish();
    else $stop();
end

// use ntw_analyzer.py for these values
// For 1 Hz excitation signal:
// calc_num_den(114.67375e6, 1) = (1, 114673750)
// calc_dds(1, 114673750) = (0, 0, 4095)
//
// For 100 kHz excitation signal:
// calc_num_den(114.67375e6, 100e3) = (80, 91739)
// calc_dds(80, 91739) = (29260, 0, 4095)

parameter KW = 18;
parameter dwi = 12;
parameter dwh = 32;
reg signed [KW-1:0] fout = 0;
reg signed [dwi-1:0] modulo = 0;
reg signed [dwi-1:0] phase_step_l = 0;
reg signed [dwh-1:0] phase_step_h = 0;
reg ntw_amp_enable = 0;
reg ntw_phs_enable = 0;

real n = 80;
real d = 91739;

real f_ref = (1e9/`DSP_CLK_CYCLE);
real q = 1/114673750;
real r = 1%114673750;
real m = (2**dwi)/114673750;
//modulo = 2**dwi - m*114673750;
//phase_step_l <= (2**dwh)*(1/114673750);
//phase_step_h <= ((2**dwh)*r)*m;

task generate_ntw(
    input real freq,
    output real f_out,
    output [dwi-1:0] modulo,
    output signed [dwi-1:0] phase_step_l,
    output signed [dwh-1:0] phase_step_h
);
begin
    // for now use already calculated values, hardware coded values
    f_out = freq/f_ref;
    @(posedge clk);
    modulo = 4095;
    @(posedge clk);
    phase_step_l <= 1;
    @(posedge clk);
    phase_step_h <= 29260;
    @(posedge clk);
end
endtask

task ntw_check(
    input real freq
);
begin
    generate_ntw(freq, fout, modulo, phase_step_l, phase_step_h);
    @(posedge clk);
    ntw_amp_enable <= 0;
    ntw_phs_enable <= 0;
end
endtask

always @(posedge clk) begin
   ntw_check(100e3); // frequency
end

wire trig;
reg [9:0] cnt = 0;
assign trig = cnt == 250 ? 1:0;

always @(posedge clk) begin
    cnt <= cnt + 1;
end

always @(posedge clk) begin
    if (cc > 100) ntw_amp_enable <= 1;
    if (cc > N-1000) ntw_amp_enable <= 0;
end

wire trig_en = (ntw_amp_enable || ntw_phs_enable) ? trig : 0;
   reg signed [KW-1:0] ntw_lo_amp = 0;
   parameter [17:0] lo_amp = 18'd20000;
   parameter cordic_gain = 1.64676;
   real amp;
   initial ntw_lo_amp = lo_amp * cordic_gain;  // (79590 * 1.64676) = 131065.7
   wire signed [KW-1:0] amp_setpoint = 1000; // counts
   wire signed [KW-1:0] phs_setpoint = 10;   // degs

   wire signed [KW-1:0] amp_setpoint_ntw;
   wire signed [KW-1:0] phs_setpoint_ntw;

    // ----------------------
    // Network analyzer feature
    // ----------------------
    ntw_analyzer #(.KW(KW))
    ntw_analyzer (
        .clk              (clk),
        .trig             (trig_en),

        .ext_amp_enable   (ntw_amp_enable),
        .ext_phs_enable   (ntw_phs_enable),
        .amp_setpoint     (amp_setpoint),
        .phs_setpoint     (phs_setpoint),

        .lo_amp           (ntw_lo_amp),
        .modulo           (modulo),
        .phase_step_l     (phase_step_l),
        .phase_step_h     (phase_step_h),

        .amp_stp_ntw      (amp_setpoint_ntw), // final amplitude setpoint after excitation
        .phs_stp_ntw      (phs_setpoint_ntw)
    );

// validation
reg signed [17:0] cosc = 0, sinc = 0;
real variance=0;
integer npt=0;
real err=10;
always @(posedge clk) begin
    if (cc > 20) begin
        cosc <= $cos(n/d*`M_TWO_PI*(cc-272))*ntw_lo_amp*1.64676;
        sinc <= $sin(n/d*`M_TWO_PI*(cc-272))*ntw_lo_amp*1.64676;
        npt +=1;
        if (cc==952) begin
            variance += (ntw_analyzer.sina-sinc)**2 + (ntw_analyzer.cosa-cosc)**2;
            err = $sqrt(variance/2/npt);
		    $display("rms error = %.3f bits", err);
		    pass = (err < 0.7);
    end
	end
end


endmodule
