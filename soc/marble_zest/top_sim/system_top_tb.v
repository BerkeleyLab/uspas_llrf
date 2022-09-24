`timescale 1 ns / 1 ps

module system_top_tb;
    localparam F_CLK = 125000000;                      // Simulated clock rate in [Hz]
    localparam CLK_PERIOD_NS = 1000000000/F_CLK/2;     // Simulated clock period in [ns]
    localparam BAUD_RATE = 9216000;                    // debug text baudrate
    reg clk=1;
    integer pass=0;
    always #CLK_PERIOD_NS begin
        clk = ~clk;
    end

    // --------------------------------------------------------------
    // Simulate adc dco clock
	// Max sampling rate 125MHz, 2-lanes 16-bit serialzation
	// t_ser = 1/(8*fs) = 1ns
	// Operation fs = 114.574MHz
	// t_ser = 1.091ns
    // --------------------------------------------------------------
    reg adc_clk_dco = 1;
    reg adc_clk     = 1;
    always #(4.3636/4) begin
        adc_clk_dco = ~adc_clk_dco;
    end
    always #4.3636 begin
        adc_clk = ~adc_clk;
    end

    // --------------------------------------------------------------
    // Simulate adc output
    // --------------------------------------------------------------
    localparam DELAY=3;  // ADJUST ME!
    localparam PATTERN=32'ha19ca19c;
    localparam DW=2;    // two lane

    reg [DW-1:0] in_p = 0;
    wire [DW-1:0] in_n = ~in_p;

    reg [31:0] shifter = PATTERN;
    integer ix=4+DELAY; // delay, adjust with bitslip, '4' is just for frame > 8 bits
    integer j;
    always @(adc_clk_dco) begin
        for (j=0; j<DW; j=j+1)
            in_p[j] <= shifter[ix];
        shifter <= {shifter[30:0],shifter[31]};
    end


    // ------------------------------------------------------------------------
    //  Handle the power on Reset
    // ------------------------------------------------------------------------
    reg reset = 1;
    reg [15:0] baud_rate=0;
    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("system_top.vcd");
            $dumpvars(5,system_top_tb);
        end
        baud_rate = F_CLK/(BAUD_RATE*8);
        $write("Baud rate: %d\n", BAUD_RATE);
        $fflush();
        repeat (100) @(posedge clk);
        reset <= 0;
        $write("UART baud_rate: %d\n", BAUD_RATE);
        $fflush();
        #200000 $display("\nSimulation finish. Not a validation test.");
        //$display("\n%8s", pass ? "PASS" : "FAIL" );
        $finish;
    end

    // ------------------------------------------------------------------------
    //  Instantiate the unit under test (top.v)
    // ------------------------------------------------------------------------
    wire uart_tx;
    wire uart_rx;
    wire [31:0] gpio_z;
    wire zest_adc_sdio_dir;
    wire zest_adc_sdio;

    wire zest_dac_sdo = 1'b0;
    //  in_p[ch] = {ADC_D0_P[ch], ADC_D1_P[ch]}
    wire [7:0] adc_d0_p = {7'b0, in_p[1]};
    wire [7:0] adc_d0_n = {7'b0, in_n[1]};
    wire [7:0] adc_d1_p = {7'b0, in_p[0]};
    wire [7:0] adc_d1_n = {7'b0, in_n[0]};
    wire [1:0] adc_dco_p = {1'b0, {adc_clk_dco}};
    wire [1:0] adc_dco_n = {1'b0, {~adc_clk_dco}};

    system_top #(
        .FCNT_WIDTH             (8)         // speed up
    ) dut(
        .GTPREFCLK_P            (clk),                  // input
        .GTPREFCLK_N            (~clk),                 // input
        .LED                    (),                     // output [7:0]
        .TWI_SCL                (),                     // inout
        .TWI_SDA                (),                     // inout
        .TWI_RST                (),                     // output
        .UART_CTS               (reset),                // input
        .UART_TX                (uart_tx),              // output
        .UART_RX                (uart_rx),              // input
        .ZEST_ADC_PDWN          (),                     // output
        .ZEST_ADC_CSB_0         (),                     // output
        .ZEST_ADC_SYNC          (),                     // output
        .ZEST_SCLK              (),                     // output
        .ZEST_SDI               (),                     // output
        .ZEST_ADC_CSB_1         (),                     // output
        .ZEST_LMK_LEUWIRE       (),                     // output
        .ZEST_PWR_SYNC          (),                     // output
        .ZEST_PWR_EN            (),                     // output
        .ZEST_AD7794_FCLK       (),                     // output
        .ZEST_DAC_CSB           (),                     // output
        .ZEST_AMC7823_SPI_SS    (),                     // output
        .ZEST_AD7794_CSB        (),                     // output
        .ZEST_DAC_RESET         (),                     // output
        .ZEST_POLL_SCLK         (),                     // output
        .ZEST_POLL_MOSI         (),                     // output
        .ZEST_ADC_SDIO_DIR      (zest_adc_sdio_dir),    // output
        .ZEST_ADC_SDIO          (zest_adc_sdio),        // inout
        .ZEST_AMC7823_SPI_MISO  (1'b0),                 // input
        .ZEST_LMK_DATAUWIRE     (1'b0),                 // input
        .ZEST_AD7794_DOUT       (1'b0),                 // input
        .ZEST_DAC_SDO           (zest_dac_sdo),         // input
        .ZEST_CLK_TO_FPGA_P     ({adc_clk, 1'b0}),      // input
        .ZEST_CLK_TO_FPGA_N     ({~adc_clk,1'b0}),      // input
        .ZEST_ADC_D0_P          (adc_d0_p),             // input [7:0]
        .ZEST_ADC_D0_N          (adc_d0_n),             // input [7:0]
        .ZEST_ADC_D1_P          (adc_d1_p),             // input [7:0]
        .ZEST_ADC_D1_N          (adc_d1_n),             // input [7:0]
        .ZEST_ADC_DCO_P         (adc_dco_p),            // input [1:0]
        .ZEST_ADC_DCO_N         (adc_dco_n),            // input [1:0]
        .ZEST_ADC_FCO_P         (2'h0),                 // input [1:0]
        .ZEST_ADC_FCO_N         (2'h0),                 // input [1:0]
        .ZEST_DAC_D_P           (),                     // output [13:0]
        .ZEST_DAC_D_N           (),                     // output [13:0]
        .ZEST_DAC_DCI_P         (),                     // output
        .ZEST_DAC_DCI_N         (),                     // output
        .ZEST_DAC_DCO_P         (1'b0),                 // input
        .ZEST_DAC_DCO_N         (1'b0),                 // input
        .ZEST_PMOD1             (),                     // inout [7:0]
        .ZEST_PMOD2             ()                      // inout [7:0]
    );

    // ------------------------------------------------------------------------
    //  Instantiate the virtual UART which receives debug data from UART0
    // ------------------------------------------------------------------------
    //  its purpose is to print debug characers to the console
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

    always @(posedge clk) begin
        if (dut.lb_rvalid) $display("\nTime: %g ns, LB Read addr: 0x%8x, data: 0x%8x.", $time, dut.lb_addr, dut.lb_rdata);
    end
    // End the simulation when the CPU falls into a `trap`
    // But wait until the UART is done receiving the last character
    always @(posedge clk) begin
        if (!reset && dut.trap && !uart_debug0.busy) begin
            $write("\n");
            $display("CPU Trap. Stop.");
            $finish;
        end
    end

endmodule
