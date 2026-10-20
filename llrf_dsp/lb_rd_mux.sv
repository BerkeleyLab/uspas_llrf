// Localbus readback mux over N windows. Window i covers
// [BASE[i], BASE[i] + 2^WAW[i]); an address in no window reads 32'hfaceface.
// The read address is registered with lb_read, and the data one read cycle
// later, as the sources (dpram, status banks) need one lb_clk to produce it:
// together with the system.v read path this keeps READ_DELAY = 3.
module lb_rd_mux #(
    parameter int N = 1,
    parameter int LB_ADW = 18,
    parameter logic [N*LB_ADW-1:0] BASE = '0,
    parameter logic [N*5-1:0] WAW = '0
) (
    input                     lb_clk,
    input                     lb_read,
    input        [LB_ADW-1:0] lb_addr,
    input        [31:0]       rdata [N],
    output logic [LB_ADW-1:0] lb_addr_d1 = '0,  // for sources selected after the dpram
    output logic [31:0]       lb_rdata = '0
);

function automatic logic hit(logic [LB_ADW-1:0] a, int i);
    logic [LB_ADW-1:0] base = BASE[i*LB_ADW +: LB_ADW];
    logic [4:0] waw = WAW[i*5 +: 5];
    return (a >> waw) == (base >> waw);
endfunction

always @(posedge lb_clk) if (lb_read) begin
    lb_addr_d1 <= lb_addr;
    lb_rdata <= 32'hfaceface;
    for (int i = 0; i < N; i++)
        if (hit(lb_addr_d1, i)) lb_rdata <= rdata[i];
end

endmodule
