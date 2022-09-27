`timescale 1ns / 1ns

// Simple parameterized time-out counter
module timeout_counter #(
    parameter TIMEOUT      = 10,       // seconds
    parameter CLOCK_PERIOD = 8.7206e-9  // seconds
) (
    input clk,
    input reset,
    input enable,
    output timeout
);
    localparam MSB = $clog2(1/CLOCK_PERIOD * TIMEOUT);
    localparam MAX_TICKS = $rtoi($ceil(1/CLOCK_PERIOD * TIMEOUT)); // convert real to an integer by truncating, for synthesis

    reg [MSB-1:0] count = 0;

    wire timeout_i = (count >= MAX_TICKS);
    assign timeout = timeout_i;

    always @(posedge clk) begin
        if (reset) begin
            count <= 0;
        end else if (enable & ~timeout_i) begin
            count <= count + 1;
        end
    end

endmodule

// Simple programmable parameterized time-out counter
module programmable_timeout (
    input clk,
    input reset,
    input enable,
    input [31:0] max_ticks,
    output timeout
);
    reg [31:0] count = 0, max_ticks_i = 0;

    wire timeout_i = (count >= max_ticks_i);
    assign timeout = timeout_i;

    always @(posedge clk) begin
        max_ticks_i <= max_ticks;
        if (reset) begin
            count <= 0;
        end else if (enable & ~timeout_i) begin
            count <= count + 1;
        end
    end

endmodule


module phase_ramp #(
    parameter KW = 18, // signal width
    parameter EW = 15  // error width (saturated)
) (
    input clk,
    input reset,
    input enable,                           // Closed phase loop indicator
    input ramp_start,                       // From EVR

    input [KW-1:0] steps,                   // No. of steps, from EPICS
    input signed [KW-1:0] ramp_rate,        // Signed slew rate, from EPICS
    input signed [KW-1:0] setpoint_start,   // Initial setpoint, from pi_scalar.v
    input signed [EW-1:0] error,            // loop error, from pi_scalar.v
    input [31:0] phase_ramp_time,           // speed of each step, from EPICS/User

    input [EW-1:0] error_threshold,         // Error threhshold, max tolerable phase error

    output signed [KW-1:0] setpoint_finish, // Final setpoint after ramping
    output ramp_finish,                     // Report when ramping is done, to EPICS
    output ramping_i,
    output timeout_i
);

//localparam [EW-1:0] ERROR_THRESHOLD = 455;  // Roughly 5 deg of tolerable phase error

reg timeout_en = 0;

reg signed [KW-1:0] setpoint = 0;
reg [KW-1:0] step_cnt = 0;
reg [1:0] start_edge = 2'b00;
reg ramping = 0, ramp_finish_i = 0;
wire dwell = in_range & ~dwell_timeout;

wire timeout, dwell_timeout;
wire reset_all = reset | ~enable; // forget old states when relocking
wire cmp = step_cnt >= steps-1; // Check if ramping is done

// wire [EW-1:0] loop_error = ((error < 0) ? -error : error); // Take the absolute value of the error
// wire in_range = loop_error < ERROR_THRESHOLD;

// To filter out any false valids in our error loop, make sure we are in range for 3 cycles
reg [7:0] in_range_shift = 8'b00000000;
wire [EW-1:0] loop_error = ((error < 0) ? -error : error); // Take the absolute value of the error
wire in_range = in_range_shift == 8'b11111111;
always @(posedge clk)
    in_range_shift <= {in_range_shift[6:0], loop_error < error_threshold};

always @(posedge clk) begin
    if (reset_all) begin
        setpoint <= 0;
        ramping <= 0;
        start_edge <= 2'b00;
        ramp_finish_i <= 0;
    end else begin
        start_edge[0] <= ramp_start;
        start_edge[1] <= start_edge[0];
    end

    // Latch the start signal on rising edge
    // and set the starting point
    if ((start_edge == 2'b01) && ~ramping) begin
        timeout_en <= 0;
        ramping <= 1;
        ramp_finish_i <= 0;
        step_cnt <= 0;
        setpoint <= setpoint_start;
    end

    // While it's ramping...
    if (ramping) begin
        if ((cmp && in_range) && dwell_timeout) begin
            ramping <= 0;
            ramp_finish_i <= 1;
        end
        else if (timeout) begin
            timeout_en <= 1;
            ramping <= 0;
        end

        if (dwell_timeout) begin
            step_cnt <= step_cnt + 1;
            setpoint <= setpoint + ramp_rate;
        end
    end
end

assign ramp_finish = ramp_finish_i;
assign setpoint_finish = setpoint;
assign ramping_i = ramping;
assign timeout_i = timeout_en;

timeout_counter timer(
    .clk    (clk),
    .reset  (dwell_timeout | ~ramping),
    .enable (~dwell_timeout & ramping),
    .timeout(timeout)
);

programmable_timeout dwell_timer(
    .clk    (clk),
    .reset  (~dwell | ~ramping),
    .enable (dwell & ramping),
    .max_ticks (phase_ramp_time),
    .timeout(dwell_timeout)
);
endmodule
