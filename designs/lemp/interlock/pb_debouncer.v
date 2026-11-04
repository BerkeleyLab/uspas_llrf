module pb_debouncer #(
    parameter integer CNT_WIDTH = 16
) (
    input clk,
    input PB,  // "PB" is the glitchy, asynchronous to clk, active high push-button signal

    // from which we make three outputs, all synchronous to the clock
    output PB_state,  // 1 as long as the push-button is active (up)
    output PB_down,  // 1 for one clock cycle when the push-button goes down (i.e. just pushed)
    output PB_up   // 1 for one clock cycle when the push-button goes up (i.e. just released)
);

// First use two flip-flops to synchronize the PB signal the "clk" clock domain
reg PB_sync_0;  always @(posedge clk) PB_sync_0 <= PB;
reg PB_sync_1;  always @(posedge clk) PB_sync_1 <= PB_sync_0;

// Next declare a 16-bits counter
reg [CNT_WIDTH-1:0] PB_cnt = 0;

reg PB_state_r = 0;

// When the push-button is pushed or released, we increment the counter
// The counter has to be maxed out before we decide that the push-button state has changed

wire PB_idle = (PB_state_r==PB_sync_1);
wire PB_cnt_max = &PB_cnt;// true when all bits of PB_cnt are 1's

always @(posedge clk)
if(PB_idle)
    PB_cnt <= 0;  // nothing's going on
else
begin
    PB_cnt <= PB_cnt + 16'd1;  // something's going on, increment the counter
    if(PB_cnt_max) PB_state_r <= PB;  // if the counter is maxed out, PB changed!
end

assign PB_down  = ~PB_idle & PB_cnt_max & ~PB_state_r;
assign PB_up    = ~PB_idle & PB_cnt_max &  PB_state_r;
assign PB_state = PB_state_r;
endmodule
