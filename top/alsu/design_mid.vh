// ALSU board IO, included at the end of marble_zest_mid.vh.
// Enabled by the DESIGN_OWNS_* and DESIGN_SOC_EXPANSION defines in
// top/alsu/Makefile.

// PMOD1: ARC detectors
assign arc_permit_in = PMOD1[6:4];
assign PMOD1[2:0]    = arc_test_out;
assign PMOD1[3]      = arc_reset_out;

// PMOD2: FO board
assign drive_permit_in = PMOD2[7];
assign slow_permit_in  = PMOD2[6];
assign PMOD2[3]        = fast_permit_out;
assign PMOD2[2]        = fast_rf_permit_out;
assign PMOD2[1]        = evg_permit_out;
assign PMOD2[0]        = hpa_permit_out;

// --------------------------------------------------------------
//  UART1 on the SoC expansion port, does Modbus-RTU over RS485 on
//  ZEST_PMOD1[3:0] (system port PMOD2). Firmware: soc/alsu/.
// --------------------------------------------------------------
wire rs485_irq_rx;
rs485_uart #(
    .BASE_ADDR   (8'h06)   // BASE_UART1 in soc/alsu/settings_design.h
) uart_inst1 (
    .clk         (clk),
    .rst         (rst),
    .M_RXD       (ZEST_PMOD1[2]),
    .M_TXD       (ZEST_PMOD1[1]),
    .M_RE_N      (ZEST_PMOD1[0]),
    .M_DE        (ZEST_PMOD1[3]),
    .irq_rx_valid(rs485_irq_rx),
    .mem_packed_fwd(ext_mem_packed_fwd),
    .mem_packed_ret(ext_mem_packed_ret)
);
assign ext_irq = {3'b0, rs485_irq_rx};  // irqFlags[4] = IRQ_UART1_RX
