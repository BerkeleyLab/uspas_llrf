// triggers with its trig_cfg_t as flat ports, so test_triggers.py drives
// width and delay by name
module test_triggers (
    input         clk,
    input         rst_n,
    input         enable,
    input  [31:0] width,
    input  [31:0] delay,
    output        pmod_trigs
);
llrf_shell_pkg::trig_cfg_t cfg;
assign cfg = '{width: width, delay: delay};
triggers dut (.clk(clk), .rst_n(rst_n), .enable(enable), .cfg(cfg),
              .pmod_trigs(pmod_trigs));
endmodule
