// Simulation models for topsim (top/common/top_rules.mk) of the Xilinx
// primitives that marble_zest_frame.sv still contains.

// XADC: the SoC's xadc_pack reads it through the DRP and waits for DRDY. This
// answers every read one clock after DEN, with the temperature register at
// 0x9772 (as soc/common/sim expects) and other registers at 0; writes are
// ignored, and no conversions run (EOC, EOS, BUSY and the alarms stay low).
module XADC #(
    parameter [15:0] INIT_40 = 16'h0, INIT_41 = 16'h0, INIT_42 = 16'h0,
    parameter [15:0] INIT_48 = 16'h0, INIT_49 = 16'h0, INIT_4A = 16'h0, INIT_4B = 16'h0,
    parameter [15:0] INIT_4C = 16'h0, INIT_4D = 16'h0, INIT_4E = 16'h0, INIT_4F = 16'h0,
    parameter [15:0] INIT_50 = 16'h0, INIT_51 = 16'h0, INIT_52 = 16'h0, INIT_53 = 16'h0,
    parameter [15:0] INIT_54 = 16'h0, INIT_55 = 16'h0, INIT_56 = 16'h0, INIT_57 = 16'h0,
    parameter [15:0] INIT_58 = 16'h0, INIT_5C = 16'h0,
    parameter SIM_DEVICE = "7SERIES",
    parameter SIM_MONITOR_FILE = "design.txt"
) (
    input CONVST, CONVSTCLK,
    input [6:0] DADDR,
    input DCLK, DEN,
    input [15:0] DI,
    input DWE, RESET,
    input [15:0] VAUXN, VAUXP,
    input VP, VN,
    output [7:0] ALM,
    output BUSY,
    output [4:0] CHANNEL,
    output reg [15:0] DO = 0,
    output reg DRDY = 0,
    output EOC, EOS,
    output JTAGBUSY, JTAGLOCKED, JTAGMODIFIED,
    output OT,
    output [4:0] MUXADDR
);
always @(posedge DCLK) begin
    DRDY <= DEN;
    if (DEN) DO <= DADDR == 7'h00 ? 16'h9772 : 16'h0;
end
assign ALM = 0;
assign {BUSY, EOC, EOS, OT, JTAGBUSY, JTAGLOCKED, JTAGMODIFIED} = 0;
assign CHANNEL = 0;
assign MUXADDR = 0;
endmodule
