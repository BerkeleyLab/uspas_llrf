`timescale 1us/1us

module arc_inlk_tb;

localparam CLK_HALFPERIOD = 500;
localparam TICK = 2*CLK_HALFPERIOD;
reg clk=1'b1;
always #CLK_HALFPERIOD clk <= ~clk;

// VCD dump file for gtkwave
initial begin
  if ($test$plusargs("vcd")) begin
    $dumpfile("arc_inlk.vcd");
    $dumpvars(2, arc_inlk_tb);
  end
end

localparam TOW = 14;
localparam TOSET = {TOW{1'b1}};
reg [TOW-1:0] r_timeout=0;
always @(posedge clk) begin
  if (r_timeout > 0) r_timeout <= r_timeout - 1;
end
wire to = ~(|r_timeout);
`define wait_timeout(sig) r_timeout = TOSET; #TICK wait ((to) || sig)

localparam F_CLK = $rtoi(1000000/(2*CLK_HALFPERIOD));

reg [2:0] permit=0;
wire [2:0] test_out;
wire board_reset;
reg reset_request=1'b0;
reg reset_latch=1'b0;
wire [2:0] permit_latch;
wire [2:0] permit_rbk;
wire permit_sum;
reg [2:0] test_mask=0;
reg test_stb=1'b0;
reg [2:0] permit_mask = 3'b111;
arc_inlk #(
  .N_CH(3),
  .F_CLK(F_CLK)
) arc_inlk_i (
  .clk(clk), // input
  .reset_latch(reset_latch), // input (stb)
  .reset_arc_dev(reset_request), // input (stb)
  .permit_mask({5'h00, permit_mask}), // input [7:0]
  .test_mask({5'h00, test_mask}), // input [7:0]
  .permit_raw_out(permit_rbk), // output [2:0]
  .permit_latch_out(permit_latch), // output [2:0]
  .permit_sum_out(permit_sum), // output
  .test_stb(test_stb), // input
  .dev_permit_in(permit), // input [2:0]
  .dev_test_out(test_out), // output [2:0]
  .dev_reset_out(board_reset) // output
);

wire busy = (|test_out) | board_reset;

// =========== Stimulus =============
initial begin
  $display("MAX_COUNT = %d", arc_inlk_i.MAX_COUNT);
  test_stb  = 1'b0;
  // Test ultra-simple readback
  permit = 3'b101;
  #(2*TICK) if (permit_rbk !== permit) begin
    $display("ERROR: permit readback = %b != input %b", permit_rbk, permit);
    $stop(0);
  end
  #(2*TICK) permit = 3'b010;
  #(2*TICK) if (permit_rbk !== permit) begin
    $display("ERROR: permit readback = %b != input %b", permit_rbk, permit);
    $stop(0);
  end
  // Test latch functionality
  #(2*TICK) permit = 3'b111;
  #(2*TICK) if (|permit_latch) begin
    $display("ERROR: permit latch = %b (expected 0)", permit_latch);
    $stop(0);
  end
  #TICK reset_latch = 1'b1;
  #TICK reset_latch = 1'b0;
  #(2*TICK) if (permit_latch != 3'b111) begin
    $display("ERROR: permit latch = %b (expected 111)", permit_latch);
    $stop(0);
  end
  // Test "test" functionality
  #(2*TICK) test_mask = 3'b101;
  test_stb  = 1'b1;
  #TICK test_stb = 1'b0;
  #(2*TICK) if (test_out !== test_mask) begin
    $display("ERROR: test pattern = %b != mask %b", test_out, test_mask);
    $stop(0);
  end
  #(2*TICK) `wait_timeout(~busy);
  if (to) begin
    $display("ERROR: Timed out waiting for ~busy");
    $stop(0);
  end
  // Test "test" functionality
  #(2*TICK) test_mask = 3'b010;
  test_stb  = 1'b1;
  #TICK test_stb = 1'b0;
  #(2*TICK) if (test_out !== test_mask) begin
    $display("ERROR: test pattern = %b != mask %b", test_out, test_mask);
    $stop(0);
  end
  #(2*TICK) `wait_timeout(~busy);
  if (to) begin
    $display("ERROR: Timed out waiting for ~busy");
    $stop(0);
  end
  // Test reset functionality
  #(2*TICK) test_mask = 3'b111;
  #TICK reset_request = 1'b1;
  #TICK reset_request = 1'b0;
  #(2*TICK) if (test_out !== 3'h0) begin
    $display("ERROR: test pattern nonzero (%b) during reset", test_out, 3'h0);
    $stop(0);
  end
  if (~board_reset) begin
    $display("Reset request failed");
    $stop(0);
  end
  #(2*TICK) `wait_timeout(~board_reset);
  if (to) begin
    $display("ERROR: Timed out waiting for ~board_reset");
    $stop(0);
  end

  $display("PASS");
  $finish(0);
end

endmodule
