`timescale 1ns / 1ns

module interlock_mon_tb;

   localparam INTERLOCKS_N = 7; // number of interlocks

	reg clk;
	integer cc;
	initial begin
		if ($test$plusargs("vcd")) begin
			$dumpfile("interlock_mon.vcd");
			$dumpvars(5, interlock_mon_tb);
		end
		for (cc=0; cc < 200; cc=cc+1) begin
			clk=0; #5;
			clk=1; #5;
		end
	end

	reg [INTERLOCKS_N-1:0] byp=0, reset=0;
	reg pll_ok=1, epics_timeout=0, lo_fault=0, admin_timeout=0;
    reg kr_amp_fault=0, bov_fault=0, boc_fault=0;

	always @(posedge clk) begin
		if (cc==10) epics_timeout <= 1;
		if (cc==11) kr_amp_fault <= 1;
		if (cc==12) kr_amp_fault <= 0;
		if (cc==15) epics_timeout <= 0;
		if (cc==20) reset[1] <= 1;
		if (cc==21) reset <= 0;
		if (cc==25) reset[3] <= 1;
		if (cc==26) reset <= 0;
		if (cc==30) kr_amp_fault <= 1;
		if (cc==31) pll_ok <= 0;
		if (cc==35) reset[3] <= 1;
		if (cc==36) reset <= 1;
		if (cc==40) kr_amp_fault <= 0;
		if (cc==42) pll_ok <= 1;
		if (cc==45) reset[3] <= 1;
		if (cc==45) reset[0] <= 1;
		if (cc==46) reset <= 1;
		if (cc==60) byp[3] <= 1;
		if (cc==62) kr_amp_fault <= 1;
		if (cc==63) kr_amp_fault <= 0;


	end

	wire [INTERLOCKS_N-1:0] intlk_fault, intlk_latch, intlk_firstf;
	wire intlk_trig;
	interlock_mon #(.wrong_lb_clk(0)) dut(
		.clk(clk), .lb_clk(clk),
		.byp(byp), .reset(reset),
		// individual sources
		.pll_ok(pll_ok),
		.epics_timeout(epics_timeout),
		.lo_fault(lo_fault),
		.kr_amp_fault(kr_amp_fault),
		.bov_fault(bov_fault),
		.boc_fault(boc_fault),
		.admin_timeout(1'b0),
		// outputs
		.intlk_fault(intlk_fault),
		.intlk_latch(intlk_latch),
		.intlk_firstf(intlk_firstf),
		.intlk_trig(intlk_trig)
	);

endmodule
