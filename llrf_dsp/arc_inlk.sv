`default_nettype none

module arc_inlk
    import llrf_shell_pkg::*;
#(
    parameter N_CH = 3,
    parameter F_CLK=125_000_000  // clk frequency [Hz], sets the 0.5 s test/reset pulse
) (
    input wire          clk,
    input wire arc_cfg_t     cfg,

    // status readout
    output logic [N_CH-1:0]   permit_raw_out,
    output logic [N_CH-1:0]   permit_latch_out,
    output logic        permit_sum_out,
    output logic        testing_out,     // test/reset pulse active

    // device interface
    input wire [N_CH-1:0]    dev_permit_in,
    output logic [N_CH-1:0]   dev_test_out,
    output logic        dev_reset_out
);

logic [N_CH-1:0] permit_latch_r=0;
logic [N_CH-1:0] permit_rbk=0;

always_ff @(posedge clk) begin
    permit_latch_r <= dev_permit_in & ({N_CH{cfg.reset_latch}} | permit_latch_r);
end

assign permit_latch_out = permit_latch_r;
assign permit_sum_out = & ( ~cfg.permit_mask[N_CH-1:0] | permit_latch_r);
assign permit_raw_out = permit_rbk;

localparam real ASSERT_TIME_S = 0.5; // 0.5 seconds
localparam MAX_COUNT = $rtoi(ASSERT_TIME_S*F_CLK);
localparam CW = $clog2(MAX_COUNT);
logic [CW-1:0] counter=0;
localparam integer COUNT_LAST = MAX_COUNT-1;  // sliced below: no parameter-width cast, which sv2v keeps

logic testing=1'b0;
logic [N_CH:0] reset_test_mask_r=0;
assign {dev_reset_out, dev_test_out} = testing ? reset_test_mask_r : {(N_CH+1){1'b0}};
// Test and reset requests are ignored while a pulse is active
assign testing_out = testing;

always_ff @(posedge clk) begin
  permit_rbk <= dev_permit_in;
  if (testing) begin
    if (counter == COUNT_LAST[CW-1:0]) begin
      testing <= 1'b0;
      counter <= 0;
    end else begin
      counter <= counter + 1;
    end
  end else begin
    if (cfg.test_stb | cfg.reset_arc_dev) begin
      // Ignore test_mask if reset requested
      if (cfg.reset_arc_dev) reset_test_mask_r <= {1'b1, {N_CH{1'b0}}};
      else reset_test_mask_r <= {1'b0, cfg.test_mask[N_CH-1:0]};
      testing <= 1'b1;
    end
  end
end

endmodule

`default_nettype wire
