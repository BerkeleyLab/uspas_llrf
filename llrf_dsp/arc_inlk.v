module arc_inlk #(
    parameter N_CH = 3,
    parameter F_CLK=125_000_000  // clk frequency [Hz], sets the 0.5 s test/reset pulse
) (
    input               clk,
    input [0:0]         reset_latch, // external single-cycle
    input [0:0]         reset_arc_dev,  // external single-cycle
    input [7:0]         permit_mask,
    input [7:0]         test_mask, // external
    input [0:0]         test_stb,  // external single-cycle

    // status readout
    output [N_CH-1:0]   permit_raw_out,
    output [N_CH-1:0]   permit_latch_out,
    output              permit_sum_out,
    output              testing_out,     // test/reset pulse active

    // device interface
    input [N_CH-1:0]    dev_permit_in,
    output [N_CH-1:0]   dev_test_out,
    output              dev_reset_out
);

reg [N_CH-1:0] permit_latch_r=0;
reg [N_CH-1:0] permit_rbk=0;

always @(posedge clk) begin
    permit_latch_r <= dev_permit_in & ({N_CH{reset_latch}} | permit_latch_r);
end

assign permit_latch_out = permit_latch_r;
assign permit_sum_out = & ( ~permit_mask[N_CH-1:0] | permit_latch_r);
assign permit_raw_out = permit_rbk;

localparam real ASSERT_TIME_S = 0.5; // 0.5 seconds
localparam MAX_COUNT = $rtoi(ASSERT_TIME_S*F_CLK);
localparam CW = $clog2(MAX_COUNT);
reg [CW-1:0] counter=0;

reg testing=1'b0;
reg [N_CH:0] reset_test_mask_r=0;
assign {dev_reset_out, dev_test_out} = testing ? reset_test_mask_r : {(N_CH+1){1'b0}};
// Test and reset requests are ignored while a pulse is active
assign testing_out = testing;

always @(posedge clk) begin
  permit_rbk <= dev_permit_in;
  if (testing) begin
    if (counter == MAX_COUNT-1) begin
      testing <= 1'b0;
      counter <= 0;
    end else begin
      counter <= counter + 1;
    end
  end else begin
    if (test_stb | reset_arc_dev) begin
      // Ignore test_mask if reset requested
      if (reset_arc_dev) reset_test_mask_r <= {1'b1, {N_CH{1'b0}}};
      else reset_test_mask_r <= {1'b0, test_mask[N_CH-1:0]};
      testing <= 1'b1;
    end
  end
end

endmodule
