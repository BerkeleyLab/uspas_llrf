/* Modbus application-specific initialization */

#include <stdint.h>
#include "init_modbus.h"
#include "settings.h"
#include "irqs.h"
#include "mb_client.h"
#include "mb_array_map.h"
#include "modbus_registers.h"
#include "uart.h"
#include "sfr.h"
#include "localbus.h"
#include "timer.h"
#include "llrf_regs_addr.h"
#include "xadc.h"

static uint16_t read_xadc_chan(uint8_t xadc_chan);

// Modbus-RTU register space (see digital_registers.h)
uint16_t reg_map[MB_REG_MAP_LEN];

extern unsigned gDebugOutputFlags;

void modbus_init(void) {
  // Init modbus-rtu driver
  UART_INIT(MODBUS_BASE_UART, MODBUS_BAUDRATE);
  SET_BLANK_RX(1);
  SET_RE_N(0);
  set_mb_regs(reg_map, MB_REG_MAP_LEN);
  //gDebugOutputFlags = DEBOUT_MODBUS; // Add this flag to enable debug prints
  _picorv32_irq_enable((1 << MODBUS_IRQ_UART));
  // Initialize memory
  for (int n=0; n < MB_REG_MAP_LEN; n++) {
    reg_map[n] = 0;
  }
  return;
}

// Called when modbus writes to a valid address in reg_map
void mb_write_callback(uint16_t mbRegId, uint16_t mbData)
{
  mb_autogen_write_callback((int)mbRegId, (int)mbData);
  return;
}

void mb_update_reg_map(int id, int mbData) {
    reg_map[id] = (uint16_t)(mbData & 0xffff);
    return;
}

unsigned int mb_get_reg_map(int id) {
    return (unsigned int)reg_map[id];
}

static uint16_t read_xadc_chan(uint8_t xadc_chan) {
    return GET_REG16(BASE_XADC + (xadc_chan<<2)) >> 4;
}

void regmap_poll(void) {
  /*
  static size_t n_frames = 0;
  // Read XADC channels. For simplicity all fractional numbers
  uint16_t xadc_data;

  if (n_frames == 0) {
    // Hand-written updates for special registers
    xadc_data = read_xadc_chan(XADC_CHAN_TEMP);
    reg_map[MB_FPGA_TEMP] = xadc_data * 503.95 / 40.96 - 273.15 * 100;  // [0.01 degC]
    xadc_data = read_xadc_chan(XADC_CHAN_VCCINT);
    reg_map[MB_FPGA_VCCINT] = xadc_data * 3000 / 4096;     // mV
    xadc_data = read_xadc_chan(XADC_CHAN_VCCAUX);
    reg_map[MB_FPGA_VCCAUX] = xadc_data * 3000 / 4096;     // mV
    xadc_data = read_xadc_chan(XADC_CHAN_VCCBRAM);
    reg_map[MB_FPGA_VCCBRAM] = xadc_data * 3000 / 4096;     // mV
    n_frames++;
  } else {
    n_frames = (n_frames < 10) ? n_frames+1 : 0;
  }
  */
  /* Auto-update normal registers */
  mb_autogen_reg_update();
  return;
}

// Testing this function which was removed from picorv32 timer.c for some reason
uint32_t reimplement_millis(void) {
  uint64_t cs = _picorv32_rd_cycle_64();
  return cs / (F_CLK / 1000);
}
