`timescale 1ns / 1ns
`include "constants.vams"
`include "settings.vams"

module phase_ramp_tb;
parameter N = 80000;
parameter P = 2/8.7206e-9;

reg clk, trace=0;
integer cc;
integer out_file;
reg pass=1;
reg done=0;
initial begin
    $display("##################################################");
    $display("    ---- Checking phase_ramp.v ----");
    if ($test$plusargs("vcd")) begin
        $dumpfile("phase_ramp.vcd");
        $dumpvars(2,phase_ramp_tb);
    end

    for (cc=0; cc < N; cc=cc+1) begin
        clk=0; #(`DSP_CLK_CYCLE/2);
        clk=1; #(`DSP_CLK_CYCLE/2);
        if (done == 1) begin
            $display("Validation: %s.", pass ? "PASS":"FAIL");
            $display("##################################################");
            if (pass) $finish();
            else $stop();
        end
    end


end

parameter speed = 100.0e-9;
reg reset = 0, enable = 0, ramp_start = 0;
reg [17:0] in_steps = 0;
reg [31:0] ramp_time = 0;
reg signed [17:0] ramp_rate = 0, setpoint_start = 0;
reg signed [17:0] stop = 0;
//wire signed [17:0] setpoint_done = $signed((steps*ramp_rate)-(ramp_rate-setpoint_start)); // exclusive of start, considers steps-1
wire signed [17:0] setpoint_done = setpoint_start + (in_steps*ramp_rate); // inclusive of start, considers steps

wire ramp_finish;
wire signed [17:0] setpoint_finish;

    task set_ramp(
        input [17:0] steps,
        input signed [17:0] rate,
        input real rtime,
        input signed [17:0] start,
        output [31:0] ramp_time_i
    );
        begin
            @(posedge clk);
            ramp_start     <= 1;
            ramp_rate      <= rate;
            setpoint_start <= start;
            in_steps       <= steps;
            ramp_time_i    <= $ceil((rtime/steps)*P); // Calculate the total ramp time in bits
            @ (posedge clk);
            ramp_start     <= 0;
        end
    endtask

    task check(
        input [17:0] steps,
        input signed [17:0] rate,
        input real rtime,
        input signed [17:0] start
    );
        begin
            set_ramp(steps, rate, rtime, start, ramp_time);
            @(posedge clk);
            @(posedge clk);
            @(ramp_finish)
                pass <= setpoint_finish == setpoint_done;
            @(posedge clk);
            $display("Time: %g ns, Initial Setpoint = %d, Final Setpoint = %d, Expected Final Setpoint = %d, at rate = %d, %s ", $realtime, start, setpoint_finish, setpoint_done, rate, pass ? "OK": "FAIL");
        end
    endtask


always @(posedge clk) begin
    @(cc==30) begin
        reset <= 1;
        enable <= 0;
    end

    @(cc==50) begin
        reset <= 0;
        enable <= 1;
    end
    // steps, rate, total ramp time, starting setpoint
    check(360, 1, 50e-9, 1);
    check(100, 1, 10e-9, 1);

    check(10, -100, 500e-9, 131070);
    check(2520, 1, 100e-9, -1);
    check(1440, 10, 200e-9, 500);
    check(500, -1000, 250e-9, -1);

    done = 1;

end

reg signed [14:0] error = 0, error_tmp = 0;

// random number generator for error
always @(posedge clk) begin
       error_tmp <= $random % 1364;
       if (error_tmp >= 1360)
           error <= error_tmp;
end
wire [14:0] error_threshold = 1366;
phase_ramp #(.KW(18)) dut(
    .clk             (clk),
    .reset           (reset),
    .enable          (enable),
    .ramp_start      (ramp_start),
    .ramp_rate       (ramp_rate),
    .phase_ramp_time (ramp_time),
    .setpoint_start  (setpoint_start),
    .error_threshold (error_threshold),
    .steps           (in_steps),
    .setpoint_finish (setpoint_finish),
    .error           (error),
    .ramp_finish     (ramp_finish)
);

endmodule
