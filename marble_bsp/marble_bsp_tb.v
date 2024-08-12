`timescale  1ns / 1ns

module marble_bsp_tb;

localparam LB_ADW     = 18;
localparam LB_READ_DELAY = 3;

localparam CLK_PERIOD = 8;

// clock generation
reg clk;
initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

wire lb_clk = clk;

    `include "localbus.vh"
    `include "regmap_marble_bsp.vh"

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
            @ (negedge clk);
            spi_wdata_val = 1'b1;
            spi_wdata = {16'h0, mode, addr, data};
            @ (negedge clk);
            spi_wdata_val = 1'b0;
            wait (~spi_busy);
        end
    endtask

    wire FPGA_CSB, FPGA_SCK, FPGA_POCI, FPGA_PICO;
    // ---------------------
    // SPI master (MMC)
    // ---------------------

    spi_engine spi_engine_i (
        .clk                (clk),
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

    marble_bsp #(
        .LB_READ_DELAY(LB_READ_DELAY)
    ) dut (
        // Ignore UDP / badger
        .RGMII_RXD      (4'h0),
        .RGMII_RX_CTRL  (1'b0),
        .RGMII_RX_CLK   (1'b0),

        .FPGA_SCK       (FPGA_SCK),
        .FPGA_CSB       (FPGA_CSB),
        .FPGA_PICO      (FPGA_PICO),
        .FPGA_POCI      (FPGA_POCI),

        .clk_locked     (1'b1),
        .gmii_tx_clk    (1'b0),
        .gmii_tx_clk90  (1'b0),
        .m_lb_rdata     (32'h0),

        .lb_clk         (lb_clk),
        .lb_addr        (lb_addr),
        .lb_write       (lb_write),
        .lb_read        (lb_read),
        .lb_rvalid      (lb_rvalid),
        .lb_wdata       (lb_wdata),
        .lb_rdata       (lb_rdata)
    );

    localparam [24:0] SPI_MBOX_BASE=24'h40_000;
    localparam [3:0]
        MBOX_CONFIG_S = 4'h1,
        MBOX_CONFIG_P = 4'h3,
        MBOX_CONFIG_R = 4'h4,
        MBOX_CONFIG_W = 4'h5;

    // Main procedure
    reg [31:0] rdata = 0;
    reg fail=0;
    reg [3:0] test_addr = 8'h2;
    reg [7:0] test_byte = 8'h13;
    initial begin
        repeat (100) @ (posedge clk);
        mmc_spi_write_task(MBOX_CONFIG_S, 4'h7, 8'h1);
        mmc_spi_write_task(MBOX_CONFIG_W, test_addr, test_byte);
        $display("Time: %g ns: MBOX write addr: %2d, data: 0x%08x.",
            $time, test_addr, test_byte);

        lb_read_task(SPI_MBOX_BASE + test_addr, rdata);
        fail |= (rdata != test_byte);
        $display("Time: %g ns:    LB read addr: %2d, data: 0x%08x, %s",
            $time, test_addr, rdata, fail ? "FAIL":"OK");
        if (!fail) $finish();
        else $stop();
    end

   initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("marble_bsp.vcd");
            $dumpvars(5, marble_bsp_tb);
        end
        #(400_000 / CLK_PERIOD);
        $display("Simulation timed-out");
        $display("FAIL");
        $stop();
   end

endmodule