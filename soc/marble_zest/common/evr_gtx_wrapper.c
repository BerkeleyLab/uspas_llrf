#include <stdbool.h>
#include <stdint.h>
#include "localbus.h"
#include "evr_gtx_wrapper.h"
#include "timer.h"
#include "printf.h"
#include "settings.h"
#include "print.h"

// Receiver alignment state machines
struct rxAligner {
    uint32_t whenEntered;
    uint32_t resetCount;
    enum rxState { S_ALIGNED, S_APPLY_RESET, S_HOLD_RESET,
                   S_AWAIT_RESET_COMPLETION, S_POST_RESET_DELAY,
                   S_POST_ALIGNMENT_DELAY } state;
};
// Initialize rxAligner instance
static struct rxAligner rxalign = {0}; // Persistent state across calls

bool check_gtx_freq(uint32_t fcnt, const char *name, uint32_t fcnt_exp) {
    printf("  Fclk %8s: ", name);
    print_udec_fix(fcnt*125, GTX_FCNT_WIDTH, 3);
    printf(" MHz\n");
    return (fcnt > fcnt_exp*0.98 && fcnt < fcnt_exp*1.02);
}

static uint32_t get_us_since_boot(void) {
    return _picorv32_rd_cycle_64() / (F_CLK / 1000000);
}

/*
 * Receiver can place its recovered clock at 20 different phases relative to
 * the incoming data.  This is not acceptable, since it affects the measurement
 * of the round-trip latency.  The receiver is configured with automatic
 * bit-slide disabled and manual bit-slide is never performed.  Instead, the
 * following state machine will repeatedly reset the receiver until the receiver
 * comes out of reset in the spot that is locked.
 */
static int gtxCrankRxAlignerFor(struct rxAligner *rxp)
{
    enum rxState oldState = rxp->state;
    uint32_t since_boot = get_us_since_boot();
    uint32_t after = since_boot - rxp->whenEntered;
    switch (rxp->state) {
    case S_ALIGNED:
        rxp->resetCount = 0;
        if (read_lb_reg(GTX_RX_ALIGNED) != 1) {
            printf("  %s: GTX misaligned after %u us.\n", __func__, after);
            rxp->state = S_APPLY_RESET;
        }
        break;

    case S_APPLY_RESET:
        rxp->resetCount++;
        if (((rxp->resetCount % 1000000) == 0)) {
            printf("  %s: GTX reset count: %d\n", __func__, rxp->resetCount);
        }
        write_lb_reg(GTX_SOFT_RESET, 1);
        rxp->state = S_HOLD_RESET;
        break;

    case S_HOLD_RESET:
        if (after > 10) {
            write_lb_reg(GTX_SOFT_RESET, 0);
            rxp->state = S_AWAIT_RESET_COMPLETION;
        }
        break;

    case S_AWAIT_RESET_COMPLETION:
        /*
         * Large timeout is to limit message rate to a reasonable value.
         * No problem since the timeout is very unlikely to ever be reached.
         */
        if (read_lb_reg(GTX_RX_RESETDONE) == 1) {
            rxp->state = S_POST_RESET_DELAY;
        }
        else if (after > 250000) {
            printf("  %s: Rx reset not done.\n", __func__);
            rxp->state = S_APPLY_RESET;
        }
        break;

    case S_POST_RESET_DELAY:
        if (read_lb_reg(GTX_RX_ALIGNED) == 1) {
            rxp->state = S_POST_ALIGNMENT_DELAY;
        }
        else if (after > 1000) {
            rxp->state = S_APPLY_RESET;
        }
        break;

    case S_POST_ALIGNMENT_DELAY:
        if (after > 250000) {
            if (read_lb_reg(GTX_RX_ALIGNED) == 1) {
                printf("  %s: GTX aligned after %d resets\n",  __func__, rxp->resetCount);
                rxp->state = S_ALIGNED;
            }
            else {
                rxp->state = S_APPLY_RESET;
            }
        }
        break;
    }
    if (rxp->state != oldState) {
        rxp->whenEntered = since_boot;
    }
    return (rxp->state == S_ALIGNED);
}


// Keeps checking if EVR GTX RX is aligned in the background
void check_gtx_align(void)
{
    gtxCrankRxAlignerFor(&rxalign);
}


bool init_evr_gtx(void) {
    bool p, pass = true;
    uint32_t boot_ts;

    boot_ts = get_us_since_boot();
    rxalign.whenEntered = boot_ts;

    p = CHECK_BIT(read_lb_reg(GTX_CPLL_LOCKED), 0); pass &= p;
    printf("  %s: GTX_CPLL_LOCKED:  %s\n", __func__, p ? "OK": "FAIL");

    p = CHECK_BIT(read_lb_reg(GTX_RX_RESETDONE), 0); pass &= p;
    printf("  %s: GTX_RX_RESETDONE: %s\n", __func__, p ? "OK": "FAIL");

    while (!(gtxCrankRxAlignerFor(&rxalign))) {
        if ((get_us_since_boot() - boot_ts) > 5000000){
            printf("  %s: Can't align GTX receiver -- will keep trying.\n", __func__);
            return false;
        }
    }

    p = CHECK_BIT(read_lb_reg(GTX_RX_ALIGNED), 0); pass &= p;
    printf("  %s: GTX_RX_ALIGNED:   %s\n", __func__, p ? "OK": "FAIL");

    DELAY_MS(100);  // for the frequency counters
    pass &= check_gtx_freq(read_lb_reg(GTX_REFCLK_FREQUENCY), "GTX REF", GTX_FCNT_EXP);
    pass &= check_gtx_freq(read_lb_reg(GTX_RX_CLK_FREQUENCY), "GTX CDR", GTX_FCNT_EXP);
    return pass;
}
