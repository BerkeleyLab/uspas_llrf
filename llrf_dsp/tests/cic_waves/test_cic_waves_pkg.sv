`ifndef TEST_CIC_WAVES_PKG_SV
`define TEST_CIC_WAVES_PKG_SV

package test_cic_waves_pkg;

    //--------------------------------------------------------------------------
    // Global parameters
    //--------------------------------------------------------------------------
    parameter int ADDR_WIDTH  = 18;

    //--------------------------------------------------------------------------
    // Address type
    //--------------------------------------------------------------------------
    typedef logic [ADDR_WIDTH-1:0] addr_t;

    // register addresses
    localparam addr_t ADDR_CBUF_DATA_BASE   = 18'h10000;
    localparam addr_t ADDR_CBUF_READY       = 18'h00001;
    localparam addr_t ADDR_CBUF_TRANSFERED  = 18'h00002;
    localparam addr_t ADDR_CBUF_FLIP        = 18'h00003;
    localparam addr_t ADDR_SLOW_READY       = 18'h00004;
    // slow_bridge readout window, see slow_bridge_shell.v (AW=7, data from 0x11)
    // mirrors 18'h109?? in designs/uspas/llrf_shell.v
    parameter int SLOW_AW = 7;
    localparam addr_t ADDR_SLOW_DATA_BASE   = 18'h00900;
    localparam addr_t ADDR_SLOW_DATA_END    = ADDR_SLOW_DATA_BASE + ((1<<SLOW_AW) - 1);

    //--------------------------------------------------------------------------
    // Helper function: check whether an address falls inside the array window
    //--------------------------------------------------------------------------
    function automatic logic addr_in_array(
        input addr_t addr, input addr_t start_addr, input addr_t end_addr);
        /* verilator lint_off UNSIGNED */
        return (addr >= start_addr) && (addr <= end_addr);
    endfunction

endpackage

`endif
