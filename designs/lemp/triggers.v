module triggers #(
    parameter TEST = 10
) (
    input         clk,
    input         rst_n,
    input         enable,
    input  [31:0] global_delay,
    input  [31:0] width,  // external
    input  [31:0] delay,  // external
    output        pmod_trigs
);

    reg [31:0] delay_total = 32'h0;
    reg [31:0] counter = 32'h0;
    reg trigger = 1'b0;

    always @(posedge clk) begin
        delay_total = global_delay + delay;
        if (enable) begin
            if (!rst_n) begin
                counter <= 32'h0;
            end else begin
                counter <= counter + 1;
                if (counter == delay_total) begin
                    trigger <= 1'b1;
                end else if (counter == (delay_total + width)) begin
                    trigger <= 1'b0;
                end
            end
        end else begin
            trigger <= 1'b0;
        end
    end

    assign pmod_trigs = trigger;

endmodule
