#include <stdbool.h>
#include <stdint.h>
#include "localbus.h"
#include "evr_gt_wrapper.h"
#include "timer.h"
#include "printf.h"
#include "settings.h"
#include "print.h"

bool check_gt_freq(uint32_t fcnt, const char *name, uint32_t fcnt_exp) {
    printf("  Fclk %8s: ", name);
    print_udec_fix(fcnt*125, GT_FCNT_WIDTH, 3);
    printf(" MHz\n");
    return (fcnt > fcnt_exp*0.98 && fcnt < fcnt_exp*1.02);
}

bool init_evr_gt(void) {
    bool p, pass = true;

    write_lb_reg(GT_SOFT_RESET, 1);
    write_lb_reg(GT_SOFT_RESET, 0);
    // EVR GT FSM should be ready within 100 resets
    for (size_t ix=0; ix<100; ix++) {
        DELAY_MS(1);
        if (CHECK_BIT(read_lb_reg(GT_RX_ALIGNED), 0))
            break;
    }
    printf("  %s: GT_RESETS:  %d\n", __func__, read_lb_reg(GT_RX_RESET_CNT));

    p = CHECK_BIT(read_lb_reg(GT_RX_RESETDONE), 0); pass &= p;
    printf("  %s: GT_RX_RESETDONE: %s\n", __func__, p ? "OK": "FAIL");

    p = CHECK_BIT(read_lb_reg(GT_RX_ALIGNED), 0); pass &= p;
    printf("  %s: GT_RX_ALIGNED:   %s\n", __func__, p ? "OK": "FAIL");

    DELAY_MS(1);  // for the frequency counters
    pass &= check_gt_freq(read_lb_reg(GT_REFCLK_FREQUENCY), "GT REF", GT_FCNT_EXP);
    pass &= check_gt_freq(read_lb_reg(GT_RX_CLK_FREQUENCY), "GT CDR", GT_FCNT_EXP);
    return pass;
}
