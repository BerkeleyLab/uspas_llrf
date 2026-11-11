// LEMP PMOD trigger: a one-shot armed by rst_n (wave_trig in the LEMP
// shell, which already carries the EVR mode delay). After rst_n rises the
// counter runs; the output is high for cfg.width clocks from counter ==
// cfg.delay, then the counter stops until the next rst_n. Fixes of the
// LEMP-branch (2e25cd9) quirks:
// - width 0 gives no pulse (the output stayed high);
// - enabling arms nothing until the next rst_n (it fired once), and a
//   stopped counter cannot wrap around and fire again;
// - rst_n during a pulse ends it and restarts the count (the output stayed
//   high until the new end).
// The output is low while enable is low.
module triggers
    import llrf_shell_pkg::*;
(
    input         clk,
    input         rst_n,
    input         enable,
    input  trig_cfg_t cfg,
    output        pmod_trigs
);

    // 33 bits, so delay + width cannot wrap
    wire [32:0] start_cnt = {1'b0, cfg.delay};
    wire [32:0] end_cnt = start_cnt + {1'b0, cfg.width};
    reg [32:0] counter = 33'h0;
    reg running = 1'b0;
    reg trigger = 1'b0;

    always @(posedge clk) begin
        if (!enable) begin
            counter <= 33'h0;
            running <= 1'b0;
            trigger <= 1'b0;
        end else if (!rst_n) begin
            counter <= 33'h0;
            running <= 1'b1;
            trigger <= 1'b0;
        end else if (running) begin
            counter <= counter + 33'd1;
            if (counter == start_cnt) trigger <= 1'b1;
            // after the set, so width 0 gives no pulse
            if (counter == end_cnt) begin
                trigger <= 1'b0;
                running <= 1'b0;
            end
        end
    end

    assign pmod_trigs = trigger;

endmodule
