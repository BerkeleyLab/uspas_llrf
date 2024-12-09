#ifndef _EVR_GTX_WRAPPER_H_
#define _EVR_GTX_WRAPPER_H_

#include <stdint.h>
#include <stdbool.h>
#include "common.h"
#include "settings.h"

#define GTX_FCNT_WIDTH           16

#ifndef EVR_GTX_REF_FREQ_MHZ
    #define EVR_GTX_REF_FREQ_MHZ 119.0
#endif
#define GTX_FCNT_EXP (EVR_GTX_REF_FREQ_MHZ) * (1<<GTX_FCNT_WIDTH) / 125

/***************************************************************************//**
 * @brief Initialize GTX and check GTX reference freq and recovered freq.
 * @return pass - true if all validation passes
*******************************************************************************/
bool init_evr_gtx(void);

/***************************************************************************//**
 * @brief Keeps aligning the EVR GTX RX if not aligned
*******************************************************************************/
void check_gtx_align(void);

/***************************************************************************//**
 * @brief Check freq in valid range
 * @param fcnt - frequency meter readout
 * @param name - clock name string
 * @param fcnt_exp - expected fcnt
 * @return pass - true if all validation passes
*******************************************************************************/
bool check_gtx_freq(uint32_t fcnt, const char *name, uint32_t fcnt_exp);

#endif
