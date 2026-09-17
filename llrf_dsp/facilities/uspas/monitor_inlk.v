module monitor_inlk #(
    parameter N_CH = 10
) (
    input           clk,

    input [15:0]    mon_data,
    input           mon_valid,
    input           mon_last,

    output          mon_valid_out,
    output [3:0]    mon_addr_out,
    output signed [15:0]   mon_amp_out,
    output signed [16:0]   mon_phs_out,

    output reg          fault_valid_out,
    output reg [3:0]    fault_addr_out,
    output reg [15:0]   fault_amp_out,
    output reg [16:0]   fault_phs_out,

    input [15:0]    amp_lo, // external
    output [3:0]    amp_lo_addr, // external address for amp_lo
    input [15:0]    amp_hi, // external
    output [3:0]    amp_hi_addr, // external address for amp_hi
    input [0:0]     reset_inlk, // external single-cycle
    input [1:0]     inlk_mode, // external
    output [3:0]    inlk_mode_addr, // external address for inlk_mode
    input [9:0]     permit_mask,

    output [N_CH-1:0] cmp_status_hi,
    output [N_CH-1:0] cmp_status_lo,
    output [N_CH-1:0] inlk_status,
    output [N_CH-1:0] first_fault_status,
    output [N_CH-1:0] inlk_latch,
    input           record_status_en,  // trigger for latching faults
    output          inlk_permit_out
);

initial begin
    fault_valid_out = 0;
    fault_addr_out = 0;
    fault_amp_out = 0;
    fault_phs_out = 0;
end

wire signed [15:0] iq_values = mon_data;

reg xy=0;
reg signed [15:0] x_value=0, y_value=0, x_value_pre=0;
always @(posedge clk) begin
    if (mon_valid) begin
        xy <= mon_last ? 0 : ~xy;
        x_value_pre <= xy ? x_value_pre : iq_values;
    end
    y_value <= xy ? mon_data : y_value;
    x_value <= x_value_pre;
end

cordicg_b22 #(.nstg(20), .width(16)) cordic_detect(
    .clk        (clk),
    .opin       ({2'b01}),
    .xin        (x_value),
    .yin        (y_value),
    .phasein    (17'b0),
    .xout       (mon_amp_out),
    .phaseout   (mon_phs_out)
);

wire mon_valid_delay, mon_last_delay;
reg_delay #(.dw(2), .len(22)) delay0(
    .clk    (clk),
    .gate   (1'b1),
    .reset  (1'b0),
    .din    ({mon_valid, mon_last}),
    .dout   ({mon_valid_delay, mon_last_delay})
);

reg [4:0] wave_cnt_pre=0; // 1 cycle earlier than mon_amp_out for reading out threshold
reg [4:0] wave_cnt=0;     // matches the frame
reg wave_valid=0;
assign amp_lo_addr = wave_cnt_pre[4:1];
assign amp_hi_addr = wave_cnt_pre[4:1];
assign inlk_mode_addr = wave_cnt_pre[4:1];

// Four interlock status bits, 1 for good (that way the system
// powers on smoothly in fail-safe mode, needs an explicit reset
// to enable RF.
// inlk_latch is inlk_valid
reg [N_CH-1:0] inlk_latch_r=0;
reg [N_CH-1:0] high=0, low=0, inlk_ok=0, first_inlk=0; // all active high
reg cmpg_lo=0, cmpg_hi=0;
wire inlk_trip = (inlk_mode=={cmpg_hi,cmpg_lo}) | ((inlk_mode==2'b10)&(cmpg_hi|~cmpg_lo));
integer ix;
always @(posedge clk) begin
    cmpg_lo  <= mon_amp_out >= amp_lo;
    cmpg_hi  <= mon_amp_out >= amp_hi;
    wave_cnt_pre <= mon_last_delay ? 0 : wave_cnt_pre + mon_valid_delay;
    wave_cnt <= wave_cnt_pre;
    wave_valid <= mon_valid_delay;
    // inlk_mode_*    trip when
    //    00  V < lower_thresh and V < upper_thresh
    //    01  lower_thresh <= V < upper_thresh
    //    10  upper_thresh <= V < lower_thresh (shouldn't happen)
    //        or V >= upper_thresh or V < lower_thresh
    //    11  V >= lower_thresh and V >= upper_thresh
    //  Interlocks trip when inlk_* are high (latched with reset below)
    if (wave_valid) begin
        for (ix = 0; ix < N_CH; ix = ix+1)
            if (wave_cnt == 2*ix+1) begin
                high[ix] <= cmpg_hi; low[ix]  <= cmpg_lo; inlk_ok[ix] <= ~inlk_trip;
            end
    end

    inlk_latch_r <= inlk_ok & ({N_CH{reset_inlk}} | inlk_latch_r);
    // stop recording at falling edge, to latch first fault and values
    if (record_status_en) begin
        first_inlk <= inlk_ok;
        fault_valid_out <= mon_valid_out;
        fault_addr_out <= mon_addr_out;
        fault_amp_out <= mon_amp_out;
        fault_phs_out <= mon_phs_out;
    end
end
assign inlk_latch  = inlk_latch_r;
assign cmp_status_hi  = high;
assign cmp_status_lo  = low;
assign first_fault_status = first_inlk;
assign inlk_status = inlk_ok;
// permit mask: 1 to include, 0 to ignore
assign inlk_permit_out = & (~permit_mask[N_CH-1:0] | inlk_latch);
assign mon_valid_out = wave_valid;
assign mon_addr_out = wave_cnt[4:1];

endmodule
