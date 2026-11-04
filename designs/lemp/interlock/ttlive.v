`timescale 1ns / 1ns

// ------------------------------------
// Time-to-live monitor
//
// Bare bones TTL monitor using an externally-provided time-base.
// time_fault is asserted whenever the counter reaches zero and will therefore
// report a fault at start of day, before timeout has been programmed.

// Counter refreshes whenever timeout is updated.

module ttlive (
   input        clk,
   input        time_pulse, // 'Decimated' time base in 'clk' domain
   input        timeout_we,
   input [15:0] timeout,    // external
   output       time_fault  // '1' when timer expires or no timer set
);
   reg [15:0] time_cnt=0;
   reg timeout_we_r=0, time_fault_r=0;

   always @(posedge clk) begin
      timeout_we_r <= timeout_we; // Delay since _we comes one cycle early

      if (timeout_we_r)
         time_cnt <= timeout;
      else if (time_pulse && time_cnt > 0)
         time_cnt <= time_cnt - 1;
      // make sure output is a registered single bit
      time_fault_r <= (time_cnt==0);
   end

   assign time_fault = time_fault_r;

endmodule
