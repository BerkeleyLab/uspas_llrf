#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include "settings.h"
#include "uart.h"
#include "printf.h"
#include "system.h"
#include "localbus.h"
#include "marble.h"
#include "xadc.h"
#include "zest.h"
#include "timer.h"
#include "llrf.h"
#include "llrf_regs_addr.h"
#include "evr_gtx_wrapper.h"

extern zest_init_t zest_init_data;
extern marble_dev_t marble;
extern zest_status_t zest;

void console(char c) {
    uint32_t *fcnt_exp = zest_init_data.fcnt_exp;
    int16_t dval;
    int32_t dval32;
    bool pass;
    size_t ix;

    switch(c){
        case '?':
            printf("?    Help\n");
            printf("r    marble ina219, xadc, qsfp\n");
            printf("t    zest ad7823, ad7794\n");
            printf("a    zest ad9653 ADC readings\n");
            printf("f    frequency and phase readings\n");
            printf("w    adc wfm test\n");
            printf("d    mailbox and marble info test\n");
            printf("l    llrf test\n");
            break;

        case 'r':
            get_marble_info(&marble);
            print_marble_status();
            break;

        case 't':
            get_zest_status(&zest);
            print_zest_status();
            break;

        case 'a':
            // sync_zest_clocks();
            for (ix=0; ix<8; ix++) {
                dval = read_zest_adc(ix);
                printf("ADC chan %d dout: %+4d\n", ix, dval);
            }
            break;

        case 'f':
            for (ix=0; ix<=3; ix++) {
                pass = check_zest_freq(ix, fcnt_exp[ix]);
                printf("Freq %d Check: %s", ix, pass ? "PASS\n" : "FAIL\n");
            }
            check_div_clk_phase(2, 0);
            printf("GTX_CPLL_LOCKED:  %s\n", CHECK_BIT(read_lb_reg(GTX_CPLL_LOCKED), 0) ? "OK": "FAIL");
            printf("GTX_RX_RESETDONE: %s\n", CHECK_BIT(read_lb_reg(GTX_RX_RESETDONE), 0) ? "OK": "FAIL");
            printf("GTX_RX_ALIGNED:   %s\n", CHECK_BIT(read_lb_reg(GTX_RX_ALIGNED), 0) ? "OK": "FAIL");
            check_gtx_freq(read_lb_reg(GTX_REFCLK_FREQUENCY), "GTX REF", GTX_FCNT_EXP);
            check_gtx_freq(read_lb_reg(GTX_RX_CLK_FREQUENCY), "GTX CDR", GTX_FCNT_EXP);
            break;

        case 'w':
            test_adc_pn9(8);
            break;

        case 'd':
            for (ix=6*16; ix<6*16+10; ix++) {  // read page 4
                dval32 = read_lb_reg(LB_MARBLE_SPI_MBOX + ix);
                printf("mbox[%u]: %x\n", ix, dval32);
            }
            for (ix=0; ix<10; ix++) {   // sizeof(marble) = 372 bytes
                dval32 = read_lb_reg(LB_BSP_INFO_BUF + ix);
                printf("info[%u]: %d\n", ix, dval32);
            }
            break;

        case 'l':
            dval32 = read_lb_reg(DDS_PHASE_STEP);
            printf("DDS_PHASE_STEP = %u\n", dval32);
            dval32 = read_lb_reg(DDS_MODULO);
            printf("DDS_MODULO = %u\n", dval32);
            dbg_read_slowbuf();
            break;

        // any other key is echoed back
        default:
            _putchar(c);
            return;
    }
}
