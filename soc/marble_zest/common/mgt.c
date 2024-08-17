#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include "localbus.h"
#include "mgt.h"
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

/*
 * Receiver can place its recovered clock at 20 different phases relative to
 * the incoming data.  This is not acceptable since it affects the measurement
 * of the round-trip latency so the receiver is configured with automatic
 * bit-slide disabled and manual bit-slide never performed.  Instead the
 * following state machine keeps resetting the receiver until the receiver
 * comes out of reset in the spot that is locked.
 */
static int mgtCrankRxAlignerFor(struct rxAligner *rxp)
{
    enum rxState oldState = rxp->state;
    switch (rxp->state) {
    case S_ALIGNED:
        rxp->resetCount = 0;
        if (read_lb_reg(GTX_RX_ALIGNED) != 1) {
            printf("GTX misaligned after %u ms.\n",
                   (read_lb_reg(US_SINCE_BOOT)) - rxp->whenEntered);
            rxp->state = S_APPLY_RESET;
        }
        break;

    case S_APPLY_RESET:
        rxp->resetCount++;
        if (((rxp->resetCount % 1000000) == 0)) {
            printf("GTX reset count %d\n", rxp->resetCount);
        }
        write_lb_reg(GTX_SOFT_RESET, 1);
        rxp->state = S_HOLD_RESET;
        break;

    case S_HOLD_RESET:
        if (((read_lb_reg(US_SINCE_BOOT)) - rxp->whenEntered) > 10) {
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
        else if (((read_lb_reg(US_SINCE_BOOT)) - rxp->whenEntered) > 250000) {
            print_str("Rx reset not done\n");
            rxp->state = S_APPLY_RESET;
        }
        break;

    case S_POST_RESET_DELAY:
        if (read_lb_reg(GTX_RX_ALIGNED) == 1) {
            rxp->state = S_POST_ALIGNMENT_DELAY;
        }
        else if (((read_lb_reg(US_SINCE_BOOT)) - rxp->whenEntered) > 1000) {
            rxp->state = S_APPLY_RESET;
        }
        break;

    case S_POST_ALIGNMENT_DELAY:
        if (((read_lb_reg(US_SINCE_BOOT)) - rxp->whenEntered) > 250000) {
            if (read_lb_reg(GTX_RX_ALIGNED) == 1) {
                printf("GTX aligned after %d resets\n", rxp->resetCount);
                rxp->state = S_ALIGNED;
            }
            else {
                rxp->state = S_APPLY_RESET;
            }
        }
        break;
    }
    if (rxp->state != oldState) {
        rxp->whenEntered = read_lb_reg(US_SINCE_BOOT);
    }
    return (rxp->state == S_ALIGNED);
}


// Keeps checking if EVR GTX RX is aligned in the background
void check_mgt_align(void)
{
    static struct rxAligner rxalign = {0}; // Persistent state across calls
    mgtCrankRxAlignerFor(&rxalign);
}


// GTX transceiver reset sequence
// see UG476, page 78
int reset_mgt(void) {
    uint32_t then;
    write_lb_reg(GTX_CPLL_RESET, 1);
    write_lb_reg(GT_RXRESET, 1);
    DELAY_MS(3);
    write_lb_reg(GTX_CPLL_RESET, 0);
    DELAY_MS(5);
    if (read_lb_reg(GTX_CPLL_LOCKED) != 1) {
        printf("GTX PLL lock is %d, not locked.\n", read_lb_reg(GTX_CPLL_LOCKED));
        return -1;
    }
    write_lb_reg(GT_RXRESET, 0);
    DELAY_MS(5);
    then = read_lb_reg(US_SINCE_BOOT);
    while (read_lb_reg(GTX_RX_RESETDONE) != 1) {
        if (read_lb_reg(US_SINCE_BOOT) - then > 100000){
            printf("EVR MGT Rx reset not done: %d\n", read_lb_reg(GTX_RX_RESETDONE));
            return -1;
        }
    }
    // Initialize rxAligner instance
    static struct rxAligner rxalign = {0}; // Persistent state across calls
    DELAY_MS(5);
    then = read_lb_reg(US_SINCE_BOOT);
    while (!(mgtCrankRxAlignerFor(&rxalign))) {
        if (read_lb_reg(US_SINCE_BOOT) - then > 5000000){
            print_str("Can't align GTX receiver -- will keep trying in background\n");
            return -1;
        }
    }
    return 0;
}
