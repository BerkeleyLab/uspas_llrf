`timescale 1ns / 1ns

module system #(
    parameter SYSTEM_HEX_PATH="system32.hex",
    parameter LB_READ_DELAY = 3,
    parameter LB_ADW     = 20
) (
    input           clk,
    input           cpu_reset,

    inout  [31:0]   gpio_z,

    output          uart_tx,
    input           uart_rx,

    output          trap,

    input               lb_write,
    input               lb_read,
    input [LB_ADW-1:0]  lb_addr,
    input [31:0]        lb_wdata,
    output [31:0]       lb_rdata,
    input               lb_rvalid,

    output              lb_merge_write,
    output              lb_merge_read,
    output [LB_ADW-1:0] lb_merge_addr,
    output [31:0]       lb_merge_wdata,
    input [31:0]        lb_merge_rdata,
    output              lb_merge_rvalid,

    output              rst,
    output [68:0]       mem_packed_fwd,
    input  [32:0]       mem_packed_ret
);

// --------------------------------------------------------------
//  Highest byte of the memory address selects peripherals, must match settings.h
// --------------------------------------------------------------
localparam BASE_MEM         = 8'h00;
localparam BASE_GPIO        = 8'h01;
localparam BASE_UART0       = 8'h02;
localparam BASE_LOCALBUS    = 8'h03;
localparam BASE_XADC        = 8'h04;
localparam BASE_FMC         = 8'h05;

// Localbus related

// --------------------------------------------------------------
//  Internal reset generator
// --------------------------------------------------------------
//  keep the cpu in reset for 0xFF cycles after the external reset was released
reg [7:0] cnt = 0;
wire [8:0] cnt_next = cnt+1;
always @(posedge clk) cnt <= (cpu_reset) ? 0 : cnt_next[8] ? 8'hff : cnt_next[7:0];
wire reset = ~cnt_next[8];

// --------------------------------------------------------------
//  Instantiate the packed picorv32 CPU core
// --------------------------------------------------------------
wire        mem_la_read;
wire        mem_la_write;
wire [31:0] mem_la_addr;
wire [31:0] mem_la_wdata;
wire [ 3:0] mem_la_wstrb;
wire [68:0] packed_cpu_fwd;
wire [32:0] packed_cpu_ret;

pico_pack cpu_inst (
    .clk           ( clk            ),
    .reset         ( reset          ),
    .trap          ( trap           ),
    .irqFlags      ( 32'd0          ), //Rising edge interrupts
    .mem_la_read   ( mem_la_read    ), //Look ahead mem interface
    .mem_la_write  ( mem_la_write   ),
    .mem_la_addr   ( mem_la_addr    ),
    .mem_la_wdata  ( mem_la_wdata   ),
    .mem_la_wstrb  ( mem_la_wstrb   ),
    .mem_packed_fwd( packed_cpu_fwd ), //CPU > PERIPHERAL
    .mem_packed_ret( packed_cpu_ret )  //CPU < PERIPHERAL
);

// --------------------------------------------------------------
//  32 bit Memory Bus
// --------------------------------------------------------------
wire [32:0] packed_mem_ret;
wire [32:0] packed_gpio_ret;
wire [32:0] packed_URT0_ret;
wire [32:0] packed_lbus_ret;
wire [32:0] packed_xadc_ret;
wire [32:0] packed_fmc_ret;
assign packed_cpu_ret = packed_mem_ret |
                        packed_gpio_ret|
                        packed_URT0_ret|
                        packed_lbus_ret|
                        packed_xadc_ret|
                        packed_fmc_ret;

// --------------------------------------------------------------
//  Instantiate the memory (holds data and program!)
//  Active from mem_addr = 0 ... MEM_SIZE-1
// --------------------------------------------------------------
`ifdef MEMORY_PACK_FAST
memory2_pack #(
    .MEM_INIT      (SYSTEM_HEX_PATH ),
    .BASE_ADDR     (BASE_MEM        )
) mem_inst (
    // Hardware interface
    .clk           (clk             ),
    .reset         (reset           ),
    // Look ahead interface
    .mem_la_read   (mem_la_read     ),
    .mem_la_write  (mem_la_write    ),
    .mem_la_addr   (mem_la_addr     ),
    .mem_la_wdata  (mem_la_wdata    ),
    .mem_la_wstrb  (mem_la_wstrb    ),
    // PicoRV32 packed MEM Bus interface
    .mem_packed_ret(packed_mem_ret  )  //CPU < MEM
);
`else
memory_pack #(
    .MEM_INIT      ( SYSTEM_HEX_PATH ),
    .BASE_ADDR     ( BASE_MEM )
) mem_inst (
    // Hardware interface
    .clk           ( clk            ),
    // PicoRV32 packed MEM Bus interface
    .mem_packed_fwd( packed_cpu_fwd ), //CPU > MEM
    .mem_packed_ret( packed_mem_ret )  //CPU < MEM
);
`endif

// --------------------------------------------------------------
//  GPIO module
// --------------------------------------------------------------
gpioz_pack #(
    .BASE_ADDR   ( BASE_GPIO )
) gpio (
    // Hardware interface
    .clk           ( clk            ),
    .reset         ( reset          ),
    // PicoRV32 packed MEM Bus interface
    .mem_packed_fwd( packed_cpu_fwd ), //CPU > GPIO
    .mem_packed_ret( packed_gpio_ret), //CPU < GPIO
    // Hardware interface
    .gpio_z        ( gpio_z         )
);

// --------------------------------------------------------------
//  UART0, prints debugging info to onboard USB serial
// --------------------------------------------------------------
uart_fifo_pack #(
    .DATA_WIDTH  ( 8 ),
    .BASE_ADDR   ( BASE_UART0 )
) uart_inst0 (
    // Hardware interface
    .clk         ( clk       ),
    .rst         ( reset     ),
    .rxd         ( uart_rx   ),
    .txd         ( uart_tx   ),
    .irq_rx_valid(),
    // PicoRV32 packed MEM Bus interface
    .mem_packed_fwd( packed_cpu_fwd ), //CPU > URT
    .mem_packed_ret( packed_URT0_ret )  //CPU < URT
);

reg [15:0] vaux_p=16'h0;
wire [15:0] vaux_n = ~vaux_p;
// --------------------------------------------------------------
//  xadc_pack module
// --------------------------------------------------------------
`ifndef SIMULATE
`ifndef YOSYS
xadc_pack #(
    .SIM_MONITOR_FILE("xadc_sim_data.txt"),
    .BASE_ADDR     (BASE_XADC)
) xadc_i (
    // Hardware interface
    .trigger_in (1'b0),
    .vp_in      (1'b0),
    .vn_in      (1'b0),
    .vaux_p     (vaux_p),
    .vaux_n     (vaux_n),

    // PicoRV32 packed MEM Bus interface
    .clk        (clk),
    .reset      (reset),
    .mem_packed_fwd( packed_cpu_fwd ),
    .mem_packed_ret( packed_xadc_ret)
);
`else
assign packed_xadc_ret = 0;
`endif
`else
assign packed_xadc_ret = 0;
`endif

// --------------------------------------------------------------
//  LBL local bus cross bar
// --------------------------------------------------------------
wire lb_merge_busy;

wire lbo_write, lbo_read;
wire [LB_ADW-1:0] lbo_addr;
wire [31:0] lbo_wdata;
wire [31:0] lbo_rdata;
wire lbo_rvalid;
lb_bridge #(
    .BASE_ADDR     ( BASE_LOCALBUS   ),
    .ADW           ( LB_ADW          ),
    .READ_DELAY    ( LB_READ_DELAY   )
) bridge (
    // PicoRV32 packed MEM Bus interface
    .clk           ( clk         ),
    .mem_packed_fwd( packed_cpu_fwd  ), //DEC > MEM
    .mem_packed_ret( packed_lbus_ret ), //DEC < MEM
    .busy          ( lb_merge_busy   ),
    .lb_write      ( lbo_write       ),
    .lb_read       ( lbo_read        ),
    .lb_addr       ( lbo_addr        ),
    .lb_wdata      ( lbo_wdata       ),
    .lb_rdata      ( lbo_rdata       ),
    .lb_rvalid     ( lbo_rvalid      )
);

lb_merge #(
    .ADW        (LB_ADW),
    .READ_DELAY (LB_READ_DELAY)
) merge (
    .clk        (clk   ),
    .busy       (lb_merge_busy),
    .lb_write_a (lbo_write  ),
    .lb_read_a  (lbo_read   ),
    .lb_wdata_a (lbo_wdata  ),
    .lb_addr_a  (lbo_addr   ),
    .lb_rdata_a (lbo_rdata),
    .lb_rvalid_a(lbo_rvalid  ),

    .lb_write_b (lb_write   ),
    .lb_read_b  (lb_read    ),
    .lb_wdata_b (lb_wdata   ),
    .lb_addr_b  (lb_addr    ),
    .lb_rdata_b (lb_rdata   ),
    .lb_rvalid_b(lb_rvalid  ),

    .lb_merge_write  (lb_merge_write   ),
    .lb_merge_read   (lb_merge_read    ),
    .lb_merge_wdata  (lb_merge_wdata   ),
    .lb_merge_addr   (lb_merge_addr    ),
    .lb_merge_rdata  (lb_merge_rdata   ),
    .lb_merge_rvalid (lb_merge_rvalid  )
);

// --------------------------------------------------------------
//  FMC(s) control
// --------------------------------------------------------------
assign rst = reset;
assign mem_packed_fwd = packed_cpu_fwd;
assign packed_fmc_ret = mem_packed_ret;

endmodule
