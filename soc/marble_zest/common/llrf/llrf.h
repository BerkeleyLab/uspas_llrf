#ifndef _LLRF_H_
#define _LLRF_H_

#include <stdint.h>
#include <stdbool.h>
#include "common.h"
#include "settings.h"

typedef struct {
    uint32_t addr;
    int32_t val;
} t_lbreg32;

typedef struct {
    size_t len;
    t_lbreg32 *regmap;
} t_init_llrf_data;

/***************************************************************************//**
 * @brief write lb reg.
*******************************************************************************/
void write_lb_reg(uint32_t addr, int32_t val);

/***************************************************************************//**
 * @brief Read lb reg, return 32bit signed value.
*******************************************************************************/
int32_t read_lb_reg(uint32_t addr);

/***************************************************************************//**
 * @brief Write and check llrf init registers.
*******************************************************************************/
bool init_llrf(t_init_llrf_data *init_data);

/***************************************************************************//**
 * @brief Wait for cbuf beinng filled before reading waveform or slow buf.
*******************************************************************************/
void wait_cbuf_ready(void);

/***************************************************************************//**
 * @brief Check readback registers and validate against known value.
 * @param regmap  -  points to known {addr, val} list.
 * @param len     -  length to compare.
*******************************************************************************/
bool check_llrf_regs(const t_lbreg32 *regmap, size_t len);

/***************************************************************************//**
 * @brief Write registers and validate against known value.
 * @param regmap  -  points to known {addr, val} list.
 * @param len     -  length to compare.
*******************************************************************************/
void write_llrf_regs(const t_lbreg32 *regmap, size_t len);

/***************************************************************************//**
 * @brief Read lb reg 8 times and return average.
 * @param addr     -  reg address
*******************************************************************************/
uint32_t read_avg_reg(uint32_t addr);

/***************************************************************************//**
 * @brief Measure MO phase and rotate internal DDS phase shift to zero out MO phase
 * @return valid if MO phase after rotation is less than 1 deg.
*******************************************************************************/
bool align_mo_phase(void);

/***************************************************************************//**
 * @brief  Reset interlock permit
*******************************************************************************/
void reset_interlock_permit(void);

/***************************************************************************//**
 * @brief  Set DAC permit
 * @param   permit -  1 to enable, 0 to disable
*******************************************************************************/
void set_llrf_dac_permit(bool permit);

/***************************************************************************//**
 * @brief  For CPU to set built-in self test result after boot
 * @param   pass -  1 is ok, 0 is fail
*******************************************************************************/
void set_llrf_bist_pass(bool pass);

/***************************************************************************//**
 * @brief print git rev id
*******************************************************************************/
void print_git_rev_id(void);

void dbg_read_slowbuf(void);
#endif
