#ifndef _EVR_GT_WRAPPER_H_
#define _EVR_GT_WRAPPER_H_

#include <stdint.h>
#include <stdbool.h>
#include "common.h"
#include "settings.h"

#define GT_FCNT_WIDTH           16

#ifndef EVR_GT_REF_FREQ_MHZ
    #define EVR_GT_REF_FREQ_MHZ 119.0
#endif
#define GT_FCNT_EXP (EVR_GT_REF_FREQ_MHZ) * (1<<GT_FCNT_WIDTH) / 125

/***************************************************************************//**
 * @brief Initialize GT and check GT reference freq and recovered freq.
 * @return pass - true if all validation passes
*******************************************************************************/
bool init_evr_gt(void);

/***************************************************************************//**
 * @brief Keeps aligning the EVR GT RX if not aligned
*******************************************************************************/
void check_gt_align(void);

/***************************************************************************//**
 * @brief Check freq in valid range
 * @param fcnt - frequency meter readout
 * @param name - clock name string
 * @param fcnt_exp - expected fcnt
 * @return pass - true if all validation passes
*******************************************************************************/
bool check_gt_freq(uint32_t fcnt, const char *name, uint32_t fcnt_exp);

#endif
