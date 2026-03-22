// system.v either interfaces to physical FPGA pins or to this testbench
// The CPU softcore and internal memory interface is both handled by system.v
// The output from UART0 is printed to the console

`timescale 1 ns / 1 ns

module system_tb;
    localparam F_CLK = 125000000;                      // Simulated clock rate in [Hz]
    localparam CLK_PERIOD_NS = 1000000000/F_CLK/2;     // Simulated clock period in [ns]
    localparam BAUD_RATE = 9216000;                    // debug text baudrate
    reg clk=1, clk_n=0;
    integer pass=0;
    always #CLK_PERIOD_NS begin
        clk = ~clk;
    end

    // ------------------------------------------------------------------------
    //  Handle the power on Reset
    // ------------------------------------------------------------------------
    reg reset = 1;
    reg [15:0] baud_rate=0;
    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("system.vcd");
            $dumpvars(5,system_tb);
        end
        baud_rate = F_CLK/(BAUD_RATE*8);
        $write("Baud rate: %d\n", BAUD_RATE);
        $fflush();
        repeat (100) @(posedge clk);
        reset <= 0;
        $write("UART baud_rate: %d\n", BAUD_RATE);
        $fflush();
        #500000 $display("Simulation finish.");
        //$display("\n%8s", pass ? "PASS" : "FAIL" );
        $finish;
    end

    // ------------------------------------------------------------------------
    //  Instantiate the unit under test (system.v)
    // ------------------------------------------------------------------------
    wire trap;
    wire uart_tx;
    wire uart_rx;
    wire i2c_scl, i2c_sda, i2c_rst;
    wire [7:0] PMOD0, PMOD1, PMOD2, PMOD3;
    wire trig_from_dsp, trig_to_dsp;

    parameter LB_ADW = 18;
    parameter LB_READ_DELAY=3;
    // localbus master
    reg lb0_write=0;
    reg lb0_read=0;
    reg [LB_ADW-1:0] lb0_addr=0;
    reg [31:0] lb0_wdata=0;
    wire [31:0] lb0_rdata;
    reg lb0_rvalid=0;

    // merged localbus master
    wire lb_write;
    wire lb_read;
    wire lb_rvalid;
    wire [LB_ADW-1:0] lb_addr;
    wire [31:0] lb_wdata;
    wire [31:0] lb_rdata;

    wire rst;
    wire [68:0]       mem_packed_fwd;
    wire [32:0]       mem_packed_ret;
    system #(
        .LB_ADW(LB_ADW),
        .LB_READ_DELAY(LB_READ_DELAY),
        .SYSTEM_HEX_PATH("./system32.hex")
    ) uut (
        .clk                (clk),
        .cpu_reset          (reset),
        .I2C_SCL            (i2c_scl),
        .I2C_SDA            (i2c_sda),
        .I2C_RST            (i2c_rst),
        .PMOD0              (PMOD0),
        .PMOD1              (PMOD1),
        .PMOD2              (PMOD2),
        .PMOD3              (PMOD3),
        .trig_from_dsp      (trig_from_dsp),
        .trig_to_dsp        (trig_to_dsp),
        .uart_tx            (uart_tx),
        .uart_rx            (uart_rx),
        .trap               (trap ),
        .lb_write           (lb0_write),
        .lb_read            (lb0_read),
        .lb_addr            (lb0_addr),
        .lb_wdata           (lb0_wdata),
        .lb_rdata           (lb0_rdata),
        .lb_rvalid          (lb0_rvalid),
        .lb_merge_write     (lb_write),
        .lb_merge_read      (lb_read),
        .lb_merge_addr      (lb_addr),
        .lb_merge_wdata     (lb_wdata),
        .lb_merge_rdata     (lb_rdata),
        .lb_merge_rvalid    (lb_rvalid),
        .rst                (rst),
        .mem_packed_fwd     (mem_packed_fwd),
        .mem_packed_ret     (mem_packed_ret)
    );

    // mirror ram to test write / read lb registers
    dpram #(.aw(8), .dw(32)) lb_mirror (
        .clka   (clk),
        .clkb   (clk),
        .addra  (lb_addr[7:0]),
        .dina   (lb_wdata),
        .wena   (lb_write),
        .addrb  (lb_addr[7:0]),
        .doutb  (lb_rdata)
    );

    wire [32:0]       mem_packed_ret_0;
    // Dummy load. replace with zest.v
    sfr_pack #(
        .BASE_ADDR      ( 8'h05 )
    ) fmc_i (
        .clk            ( clk        ),
        .rst            ( rst ),
        .mem_packed_fwd ( mem_packed_fwd ),
        .mem_packed_ret ( mem_packed_ret_0 ),
        .sfRegsOut      ( ),
        .sfRegsIn       ( 32'h0 ),
        .sfRegsWrStr    ( )
    );

    assign mem_packed_ret = mem_packed_ret_0;

    // ------------------------------------------------------------------------
    //  Instantiate the virtual UART which receives debug data from UART0
    // ------------------------------------------------------------------------
    //  its purpose is to print debug characters to the console
    wire [7:0] urx_tdata0;
    wire       urx_tvalid0;
    reg        urx_tready0;

    uart_rx #(
        .DATA_WIDTH(8)                // We transmit / receive 8 bit words + 1 start and stop bit
    ) uart_debug0 (
        .prescale( baud_rate ),
        .clk ( clk ),
        .rst ( reset  ),            // UART expects an active high reset
        // axi output
        .output_axis_tdata(  urx_tdata0 ),
        .output_axis_tvalid( urx_tvalid0 ),
        .input_axis_tready( urx_tready0 ),
        // uart pins
        .rxd( uart_tx )
    );

    always @(posedge clk) begin
        urx_tready0 <= 0;
        // If the virtual debug UART received data, print it to the console
        if (!reset && urx_tvalid0 && !urx_tready0) begin
            $write("%c", urx_tdata0);
            $fflush();
            urx_tready0 <= 1;
        end
    end

    // End the simulation when the CPU falls into a `trap`
    // But wait until the UART is done receiving the last character
    always @(posedge clk) begin
        if (!reset && trap && !uart_debug0.busy) begin
            $write("\n");
            $display("CPU Trap. Stop.");
            $finish;
        end
    end

    pullup (i2c_scl);
    pullup (i2c_sda);
    wire [7:0] i2c_ioout;
    i2c_model #(
        .I2C_ADR    ( 7'h74   )
    ) i2c_model (
        .SDA        ( i2c_sda ),
        .SCL        ( i2c_scl ),
        .IOout      ( i2c_ioout)
    );

    // simulate an external trigger connected to PMOD0[0] and PMOD3[0]
    reg [15:0] clk_counter=0;
    always @(posedge clk) clk_counter <= clk_counter + 1;
    assign PMOD3[1] = (clk_counter > 10) ? clk_counter[12] : 1'bz;
    // assign PMOD0[0] = (clk_counter > 10) ? clk_counter[11] : 1'bz;
    always @(posedge trig_to_dsp) $display("\n ext trigger at time %g ns", $time);

    // simulate an internal trigger
    assign trig_from_dsp = clk_counter[11];
    always @(posedge trig_from_dsp) $display("\n int trigger at time %g ns", $time);

endmodule
