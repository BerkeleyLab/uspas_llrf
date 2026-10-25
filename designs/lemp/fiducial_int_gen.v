module fiducial_int_gen #(
    parameter EVENT_NUM = 4,                     // Number of event codes decoded by timing_core_local
    parameter integer EV_ACCL = 151,
    parameter integer EV_STBY = 152,
    parameter integer CYCLE_COUNT_MAX = 7
) (
    input lb_clk,                                // lb_clk 125 MHz clock
    input dsp_clk,                               // dsp_clk 119 MHz clock
    input reset,
    input [EVENT_NUM-1:0] event_strobes,         // Strobe inputs from event receiver
    input [7:0] event_sel,                       // 0: Standby mode, 1: Accelerate mode
    input [31:0] trig_acc_delay,
    input [31:0] trig_stb_delay,

    output reg fiducial_int = 0,                 // Single-cycle pulse output
    output reg [31:0] global_delay = 0,          // Delay value based on selected event
    output [27:0] acc_cycles,
    output [27:0] stb_cycles
);

    // Event strobe indices
    // Should match how the events are passed through event_strobes
    localparam FIDU_IDX = 2;
    localparam ACCL_IDX = 0;
    localparam STBY_IDX = 1;

    // State machine
    reg [31:0] cycle_count = 0;
    reg message_active = 0;                 // Flag indicating we're processing a message

    // Event detection registers
    reg acc_detected = 0;
    reg stb_detected = 0;

    // Diagnostics
    reg fiducial_int_acc = 0;
    reg fiducial_int_stb = 0;

    always @(posedge dsp_clk or posedge reset) begin
        if (reset) begin
            cycle_count <= 3'd0;
            message_active <= 1'b0;
            acc_detected <= 1'b0;
            stb_detected <= 1'b0;
            fiducial_int <= 1'b0;
            global_delay <= 32'd0;
        end else begin
            // Default: fiducial_int is only high for one cycle
            fiducial_int <= 1'b0;
            fiducial_int_acc <= 1'b0;
            fiducial_int_stb <= 1'b0;

            // Detect message start (event_strobes[0] goes high)
            if (event_strobes[FIDU_IDX] && !message_active) begin
                message_active <= 1'b1;
                cycle_count <= 3'd0;
                // Clear detection flags for new message
                acc_detected <= 1'b0;
                stb_detected <= 1'b0;
            end

            // During message, collect events
            if (message_active) begin
                // Capture Accelerate event
                if (event_strobes[ACCL_IDX]) begin
                    acc_detected <= 1'b1;
                end

                // Capture Standby event (event code 6)
                if (event_strobes[STBY_IDX]) begin
                    stb_detected <= 1'b1;
                end

                // Count cycles
                if (cycle_count < CYCLE_COUNT_MAX) begin
                    cycle_count <= cycle_count + 1;
                end else begin
                    // All event codes evaluated - take action on next cycle
                    message_active <= 1'b0;

                    // Decision logic based on mode
                    if (event_sel == EV_STBY) begin
                        // Standby mode: always use Standby
                        if (stb_detected) begin
                            fiducial_int <= 1'b1;
                            fiducial_int_stb <= 1'b1;
                            global_delay <= trig_stb_delay;
                        end
                    end
                    else if (event_sel == EV_ACCL) begin
                        // Accelerate mode: use Accelerate if present, else Standby
                        if (acc_detected) begin
                            fiducial_int <= 1'b1;
                            fiducial_int_acc <= 1'b1;
                            global_delay <= trig_acc_delay;
                        end else if (stb_detected) begin
                            fiducial_int <= 1'b1;
                            fiducial_int_stb <= 1'b1;
                            global_delay <= trig_stb_delay;
                        end
                    end
                end
            end
        end
    end

    // Measure acc and stb internal fiducal frequency
    wire [1:0] fids = {fiducial_int_stb, fiducial_int_acc};
    wire [27:0] fids_freqs[1:0];
    reg ref_strobe=0;  reg [27:0] ref_cnt=0;
    always @(posedge lb_clk) {ref_strobe, ref_cnt} <= ref_cnt + 1'b1;
    assign acc_cycles = fids_freqs[0];
    assign stb_cycles = fids_freqs[1];

    genvar freq_i;
    generate for(freq_i=0; freq_i<2; freq_i=freq_i+1) begin: freq_gcount_logic
        freq_gcount fcounter(
            .f_in(fids[freq_i]),
            .g_in(1'b1),
            .sysclk(lb_clk),
            .ref_strobe(ref_strobe),
            .frequency(fids_freqs[freq_i])
        );
    end endgenerate

endmodule
