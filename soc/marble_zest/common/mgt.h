#ifndef _MGT_H_
#define _MGT_H_

#include <stdint.h>
#include <stdbool.h>
#include "common.h"
#include "settings.h"

/***************************************************************************//**
 * @brief Reset EVR MGT
*******************************************************************************/
int reset_mgt(void);
/***************************************************************************//**
 * @brief Keeps aligning the EVR MGT RX if not aligned
*******************************************************************************/
void check_mgt_align(void);
#endif
