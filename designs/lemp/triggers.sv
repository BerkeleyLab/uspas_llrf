// LEMP PMOD trigger: after rst_n rises a counter runs; the output is high
// for cfg.width clocks from counter == global_delay + cfg.delay, and low
// while enable is low. From the LEMP branch (2e25cd9); delay_total, a
// blocking assignment in the clocked block there, is the same sum as a wire.
module triggers
    import llrf_shell_pkg::*;
(
    input         clk,
    input         rst_n,
    input         enable,
    input  [31:0] global_delay,
    input  trig_cfg_t cfg,
    output        pmod_trigs
);

    wire [31:0] delay_total = global_delay + cfg.delay;
    reg [31:0] counter = 32'h0;
    reg trigger = 1'b0;

    always @(posedge clk) begin
        if (enable) begin
            if (!rst_n) begin
                counter <= 32'h0;
            end else begin
                counter <= counter + 1;
                if (counter == delay_total) begin
                    trigger <= 1'b1;
                end else if (counter == (delay_total + cfg.width)) begin
                    trigger <= 1'b0;
                end
            end
        end else begin
            trigger <= 1'b0;
        end
    end

    assign pmod_trigs = trigger;

endmodule
