// This file is used by
//   marble_zest_top.v (synthesis) and marble_zest_frame.v (simulation)
// It instantiates
//   system()  // PicoRV Subsystem
//   config_romx()
//   llrf_shell()
//   marble_bsp()
// and handles localbus segmentation based on lb_addr[21:18]
//   0  to llrf_shell
//   1  to marble_bsp
//   others not (yet) used

// localbus master declaration, driven by badger (located inside marble_bsp)
wire        m_lb_clk;
wire        m_lb_write;
wire        m_lb_read;
wire        m_lb_rvalid;
wire [23:0] m_lb_addr;
wire [31:0] m_lb_wdata;
wire [31:0] m_lb_rdata;
wire        m_lb_prefill;
wire [7:0]  mac_status;

assign clk = m_lb_clk;
wire lb_prefill = m_lb_prefill;

// localbus declaration
wire lb_clk = clk;
wire lb_write;
wire lb_read;
wire lb_rvalid;
wire [21:0] lb_addr;
wire [31:0] lb_wdata;
wire [31:0] lb_rdata;

wire [31:0] gpio_z;
wire rst;
wire [68:0] mem_packed_fwd;
wire [32:0] mem_packed_ret;
wire trap;

reg uart_cts1=0, uart_cts2=0;
always @(posedge clk) begin
    uart_cts1 <= UART_CTS;  // likely IOB FF
    uart_cts2 <= uart_cts1;
end
wire uart_cts_r = uart_cts1 & ~uart_cts2;  // leading-edge detect
// keep system in reset before idelayctrl is ready
wire reset_system = uart_cts_r | ~idelayctrl_ready;

// ----------------------------------
// PicoRV Subsystem
// ---------------------------------
// 22 bit local bus address width
// 4 bit msb multiplexing
// 18 bit peripheral address width
system #(
    .LB_READ_DELAY(LB_READ_DELAY),
    .LB_ADW(22),
    .SYSTEM_HEX_PATH("system32.dat")
) system_inst (
    .clk            (clk),
    .cpu_reset      (reset_system),
    .gpio_z         (gpio_z),
    .uart_tx        (UART_TX),
    .uart_rx        (UART_RX),
    .trap           (trap ),
    .lb_write       (m_lb_write),
    .lb_read        (m_lb_read),
    .lb_addr        (m_lb_addr[21:0]),
    .lb_wdata       (m_lb_wdata),
    .lb_rdata       (m_lb_rdata),
    .lb_rvalid      (m_lb_rvalid),
    .lb_merge_write (lb_write),
    .lb_merge_read  (lb_read),
    .lb_merge_addr  (lb_addr),
    .lb_merge_wdata (lb_wdata),
    .lb_merge_rdata (lb_rdata),
    .lb_merge_rvalid(lb_rvalid),
    .rst            (rst),
    .mem_packed_fwd (mem_packed_fwd),
    .mem_packed_ret (mem_packed_ret)
);

// Localbus multiplixer
//     0 to 3ffff: lb_base_0
// 40000 to 7ffff: lb_base_1
// 80000 to bffff: lb_base_2
// c0000 to fffff: lb_base_3
// ...
wire [3:0] lb_addr_mux = lb_addr[18+:4];
wire lb_base_0 = (lb_addr_mux == 4'h0);
wire lb_base_1 = (lb_addr_mux == 4'h1);
wire lb_base_2 = (lb_addr_mux == 4'h2);
wire lb_base_3 = (lb_addr_mux == 4'h3);
wire lb_write_0 = lb_write & lb_base_0;
wire lb_write_1 = lb_write & lb_base_1;
wire lb_write_2 = lb_write & lb_base_2;
wire lb_write_3 = lb_write & lb_base_3;
wire lb_read_0  = lb_read & lb_base_0;
wire lb_read_1  = lb_read & lb_base_1;
wire lb_read_2  = lb_read & lb_base_2;
wire lb_read_3  = lb_read & lb_base_3;
wire [31:0] lb_rdata_0, lb_rdata_1, lb_rdata_2, lb_rdata_3;
reg [31:0] lb_rdata_r=0;

`ifndef GIT_32BIT_ID
`define GIT_32BIT_ID 32'hdeadf00d
`endif
wire [31:0] git_rev_id = `GIT_32BIT_ID;

wire [15:0] config_rom_out;
config_romx config_romx(
    .clk    (lb_clk),
    .address(lb_addr[10:0]),
    .data   (config_rom_out)
);

// marble_zest_top.json:
// 11-bit ROM address: 0x4000 to 0x47ff
wire json_rom_sel = (lb_addr[21:11] == 11'b00_0000_0100_0);
wire git_rev_id_sel = (lb_addr == 22'h0);

always @(*) begin
    case(lb_addr_mux)
    4'h0: lb_rdata_r = lb_rdata_0;
    4'h1: lb_rdata_r = lb_rdata_1;
    default: lb_rdata_r = 32'hdeaddead;
    endcase
end
assign lb_rdata = git_rev_id_sel ? git_rev_id :
                    json_rom_sel ? config_rom_out : lb_rdata_r;

// ----------------------------------
// LLRF Subsystem, @ lb_base_0
// ---------------------------------
wire        dsp_clk;
wire [1:0]  clk_div_out;
wire [16*8-1:0] adc_out_data;
wire [7:0]  adc_out_clk;
wire [15:0] dac_a_out;
wire [15:0] dac_b_out;
wire gtx_rxclk;
wire [1:0] gtx_rxcharisk;
wire [15:0] gtx_rxdata;
wire [2:0] arc_permit_in=0;  // XXX hook me up!
wire [15:0] etrig_pulse_cnt;
wire       etrig_pulse;
wire       etrig_pulse_delay;
wire       trig_out;
llrf_shell llrf_inst (
    .lb_clk         (lb_clk),
    .lb_addr        (lb_addr[17:0]),
    .lb_write       (lb_write_0),
    .lb_read        (lb_read_0),
    .lb_wdata       (lb_wdata),
    .lb_rdata       (lb_rdata_0),
    .lb_rvalid      (lb_rvalid),
    .lb_prefill     (lb_prefill),

    .dsp_clk        (dsp_clk),
    .adc_data_in    (adc_out_data),
    .dac_data_a_out (dac_a_out),
    .dac_data_b_out (dac_b_out),

    .drive_permit_in (1'b1),
    .slow_permit_in  (1'b1),
    .arc_permit_in   (arc_permit_in),
    // to EVR
    .gtx_rxclk       (gtx_rxclk),
    .gtx_rxdata      (gtx_rxdata),
    .gtx_rxcharisk   (gtx_rxcharisk),
    // to wave trigger
    .trig_out         (trig_out),
    .etrig_pulse_cnt  (etrig_pulse_cnt),
    .etrig_pulse      (etrig_pulse),
    .etrig_pulse_delay(etrig_pulse_delay)
);

// ----------------------------------
// Marble Board Support (MMC, Badger, GTX, etc.), @ lb_base_1
// ---------------------------------
marble_bsp #(
    .IP(IP), .MAC(MAC), .LB_READ_DELAY(LB_READ_DELAY)
) marble_inst (
    .gmii_tx_clk    (gmii_tx_clk  ),
    .gmii_txd       (gmii_txd     ),
    .gmii_tx_en     (gmii_tx_en   ),
    .gmii_tx_er     (gmii_tx_er   ),

    .gmii_rx_clk    (gmii_rx_clk  ),
    .gmii_rxd       (gmii_rxd     ),
    .gmii_rx_dv     (gmii_rx_dv   ),
    .gmii_rx_er     (gmii_rx_er   ),

    .PHY_RSTN       (PHY_RSTN     ),

    .FPGA_SCK       (FPGA_SCK     ),
    .FPGA_CSB       (FPGA_CSB     ),
    .FPGA_PICO      (FPGA_PICO    ),
    .FPGA_POCI      (FPGA_POCI    ),

    .BOOT_CS_B      (BOOT_CS_B    ),
    .BOOT_CCLK      (BOOT_CCLK    ),
    .BOOT_MISO      (BOOT_MISO    ),
    .BOOT_MOSI      (BOOT_MOSI    ),

    .dsp_clk        (dsp_clk      ),
    .clk_200        (clk_200      ),
    .clk_locked     (clk_locked   ),
    .gtx_refclk     (gtx_refclk   ),
    .gtx_rxclk      (gtx_rxclk    ),

    .m_lb_clk       (m_lb_clk     ),
    .m_lb_addr      (m_lb_addr     ),
    .m_lb_write     (m_lb_write    ),
    .m_lb_read      (m_lb_read     ),
    .m_lb_wdata     (m_lb_wdata    ),
    .m_lb_rdata     (m_lb_rdata    ),
    .m_lb_rvalid    (m_lb_rvalid   ),
    .m_lb_prefill   (m_lb_prefill  ),

    .lb_clk         (lb_clk        ),
    .lb_addr        (lb_addr[17:0] ),
    .lb_write       (lb_write_1    ),
    .lb_read        (lb_read_1     ),
    .lb_wdata       (lb_wdata      ),
    .lb_rdata       (lb_rdata_1    ),
    .lb_rvalid      (lb_rvalid     ),

    .evr_gtx_rxn    (MGT_RX_6_N    ),
    .evr_gtx_rxp    (MGT_RX_6_P    ),
    .gtx_rxdata     (gtx_rxdata    ),
    .gtx_rxcharisk  (gtx_rxcharisk ),

    .in_use         (in_use        ),
    .mac_status     (mac_status    ),

    .zest_pmod      (ZEST_PMOD2[3:0]),
    .pmod_J12       (PMOD1[3:0]     ),
    .pmod_J12_dir   (PMOD1[7:4]     ),
    .etrig_pulse_cnt(etrig_pulse_cnt),
    .etrig_pulse    (etrig_pulse   ),
    .etrig_pulse_delay(etrig_pulse_delay)
);
