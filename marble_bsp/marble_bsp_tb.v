`timescale  1ns / 1ps

module marble_bsp_tb;
`include "settings.vams"
`include "regmap_marble_bsp.vh"

localparam LB_ADW           = 18;
localparam LB_READ_DELAY    = 3;
parameter real LB_CLK_CYCLE      = 8.0;   // ns
parameter real GTX_REF_CLK_CYCLE = 1000.0 / `EVR_GTX_REF_FREQ_MHZ;  // ns

// DSP clock generation
reg dsp_clk;
initial begin
    dsp_clk = 0;
    forever #(`DSP_CLK_CYCLE/2) dsp_clk = ~dsp_clk;
end


// GTX clock generation
reg gtx_clk;
initial begin
    gtx_clk = 0;
    #(1.1);  // phase shift that might be discovered by phase_diff_evr?
    forever #(GTX_REF_CLK_CYCLE/2) gtx_clk = ~gtx_clk;
end
// 200 MHz clock generation
reg clk_200;
initial begin
    clk_200 = 0;
    forever #(2.500) clk_200 = ~clk_200;
end
// Localbus clock generation
reg lb_clk;
initial begin
    lb_clk = 0;
    forever #(LB_CLK_CYCLE/2) lb_clk = ~lb_clk;
end


    `include "localbus.vh"

    reg spi_wdata_val=0;
    reg [31:0] spi_wdata=0;
    wire spi_busy;

    // from mmc_mailbox.v:
    // Mailbox pseudo-SPI protocol
    // 16-bit SPI word semantics:
    //   0 0 0 1 a a a a d d d d d d d d  ->  set MAC/IP config[a] = D
    //   0 0 1 0 0 0 0 0 x x x x x x x V  ->  set enable_rx to V
    //   0 0 1 0 0 0 1 0 x d d d d d d d  ->  set 7-bit mailbox page selector
    //   0 0 1 1 a a a a d d d d d d d d  ->  set UDP port config[a] = D
    //   0 1 0 0 a a a a d d d d d d d d  ->  mailbox read
    //   0 1 0 1 a a a a d d d d d d d d  ->  mailbox write
    task mmc_spi_write_task (
        input [3:0] mode,
        input [3:0] addr,
        input [7:0] data
    );
        begin
            wait (~spi_busy);
            @ (negedge lb_clk);
            spi_wdata_val = 1'b1;
            spi_wdata = {16'h0, mode, addr, data};
            @ (negedge lb_clk);
            spi_wdata_val = 1'b0;
            wait (~spi_busy);
        end
    endtask

    wire FPGA_CSB, FPGA_SCK, FPGA_POCI, FPGA_PICO;
    // ---------------------
    // SPI master (MMC)
    // ---------------------

    spi_engine spi_engine_i (
        .clk                (lb_clk),
        .reset              (1'b0),
        .wdata_val          (spi_wdata_val),
        .wdata              (spi_wdata),
        .busy               (spi_busy),
        // derived from mmc_mailbox_tb.v
        .cfg_sckhalfperiod  (8'd10),
        .cfg_scklen         (8'd16),
        .cfg_cpol           (1'b0),
        .cfg_cpha           (1'b1),
        .cfg_lsb            (1'b0),

        .cs                 (FPGA_CSB),
        .sck                (FPGA_SCK),
        .copi               (FPGA_PICO),
        .cipo               (FPGA_POCI)
    );

    // ---------------------
    // DUT
    // ---------------------

    localparam FCNT_WIDTH = 8;
    marble_bsp #(
        .LB_READ_DELAY      (LB_READ_DELAY),
        .FCNT_WIDTH         (FCNT_WIDTH),
        .EVR_COMMAS_NEEDED  (20),
        .EVR_CHECK_TIMEOUT  (30)
    ) dut (
        // Ignore Ethernet / Packet Badger for now
        .gmii_tx_clk    (1'b0),
        .gmii_rx_clk    (1'b0),
        .gmii_rxd       (8'h0),
        .gmii_rx_dv     (1'b0),
        .gmii_rx_er     (1'b0),

        .FPGA_SCK       (FPGA_SCK),
        .FPGA_CSB       (FPGA_CSB),
        .FPGA_PICO      (FPGA_PICO),
        .FPGA_POCI      (FPGA_POCI),

        .BOOT_MISO      (1'b0),

        .clk_locked     (1'b1),
        .m_lb_rdata     (32'h0),
        .dsp_clk        (dsp_clk),
        .clk_200        (clk_200),

        .lb_clk         (lb_clk),
        .lb_addr        (lb_addr),
        .lb_write       (lb_write),
        .lb_read        (lb_read),
        .lb_rvalid      (lb_rvalid),
        .lb_wdata       (lb_wdata),
        .lb_rdata       (lb_rdata),

        .gtx_refclk     (gtx_clk),
        .evr_gtx_rxp    (1'b0),
        .evr_gtx_rxn    (1'b0)
    );

    localparam [24:0] SPI_MBOX_BASE=24'h41_000;
    localparam [3:0]
        MBOX_CONFIG_S = 4'h1,
        MBOX_CONFIG_P = 4'h3,
        MBOX_CONFIG_R = 4'h4,
        MBOX_CONFIG_W = 4'h5;

    // Main procedure
    reg [31:0] rdata=0;
    reg fault, fail=0;
    reg [3:0] test_addr = 8'h2;
    reg [7:0] test_byte = 8'h15;
    // #define GTX_FCNT_EXP (EVR_GTX_REF_FREQ_MHZ) * (1<<GTX_FCNT_WIDTH) / 125
    reg [31:0] freq_cnt_expect = 2**FCNT_WIDTH * LB_CLK_CYCLE / GTX_REF_CLK_CYCLE;

    initial begin
        repeat (100) @ (posedge lb_clk);
        $display("---- Check MBOX SPI write / localbus read ----");
        // write through SPI
        mmc_spi_write_task(MBOX_CONFIG_S, 4'h7, 8'h1);
        mmc_spi_write_task(MBOX_CONFIG_W, test_addr, test_byte);
        // read through localbus
        lb_read_task(SPI_MBOX_BASE + test_addr, rdata);
        fault = rdata != test_byte;
        $display("Time: %g ns: rdata = %5d, expect = %5d, %s",
            $time, rdata, test_byte, fault ? "FAIL":" OK");
        fail |= fault;

        test_byte = 8'h30;
        // write/read through localbus to mailbox
        $display("---- Check MBOX localbus write/read ----");
        lb_write_task(SPI_MBOX_BASE + test_addr, test_byte);
        lb_read_task(SPI_MBOX_BASE + test_addr, rdata);
        fault = rdata != test_byte;
        $display("Time: %g ns: rdata = %5d, expect = %5d, %s",
            $time, rdata, test_byte, fault ? "FAIL":" OK");
        fail |= fault;

        // read only register through localbus
        // this is the frequency counter for GTX reference frequency
        $display("---- Check GTX_REFCLK Frequency ----");
        #(LB_CLK_CYCLE * (1 << FCNT_WIDTH));
        lb_read_task(GTX_REFCLK_FREQUENCY, rdata);
        fault = rdata > freq_cnt_expect + 1 || rdata < freq_cnt_expect - 1;
        $display("Time: %g ns: rdata = %5d, expect = %5d, %s",
            $time, rdata, freq_cnt_expect, fault ? "FAIL":" OK");
        fail |= fault;

        repeat (100) @ (posedge lb_clk);
        $display("---- Check EVR soft reset logic ----");
        lb_write_task(GTX_SOFT_RESET, 1);
        lb_write_task(GTX_SOFT_RESET, 0);
        lb_read_task(GTX_RX_ALIGNED, rdata);
        while (!lb_rdata[0]) begin
            lb_read_task(GTX_RX_ALIGNED, rdata);
        end
        $display("Time: %g ns: evr_gtx clock aligned.", $time);

        $display("---- Check EVR fsm logic ----");
        // inject data error, take 3 gt_soft_resets until clock is aligned
        dut.evr_gtx_wrapper_i.rxnotintable_out_reg = 2'b1;
        repeat (3) @(posedge dut.evr_gtx_wrapper_i.rx_fsm_reset_done);
        dut.evr_gtx_wrapper_i.rxnotintable_out_reg = 2'b0;
        @(posedge dut.evr_gtx_wrapper_i.rx_aligned_sys);
        $display("Time: %g ns: evr_gtx clock aligned.", $time);
        if (!fail) begin $display("PASS"); $finish(); end
        else $stop();
    end

   initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("marble_bsp.vcd");
            $dumpvars(5, marble_bsp_tb);
        end
        #(10_000 * LB_CLK_CYCLE);
        #(LB_CLK_CYCLE * (1 << FCNT_WIDTH));
        $display("Time: %g ns: Simulation timed-out.", $time);
        $display("FAIL");
        $stop();
   end

endmodule
