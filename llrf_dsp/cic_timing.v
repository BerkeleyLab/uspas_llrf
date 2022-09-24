// max 127 wave_samp_per
// sample_wave = cic_period * wave_samp_per
// CIC_BASE_PERIOD < 128

module cic_timing #(
    parameter CIC_BASE_PERIOD = 44
) (
    input clk,
    input [6:0] wave_samp_per,
    output cic_sample,
    output sample_wave
);

reg [6:0] cic_state=0;
reg cic_sample_r=0;
reg [6:0] wave_cnt=4;
always @(posedge clk) begin
    cic_state <= cic_state==(CIC_BASE_PERIOD-1) ? 0 : cic_state+1;
    cic_sample_r <= cic_state==0;
    if (cic_sample_r) wave_cnt <= sample_wave ? wave_samp_per : wave_cnt-1;
end
assign cic_sample = cic_sample_r;
assign sample_wave = wave_cnt==1;

endmodule
