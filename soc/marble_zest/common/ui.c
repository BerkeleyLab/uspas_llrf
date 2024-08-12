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

extern zest_init_t zest_init_data;

void handle_ui( void ) {
    uint32_t *fcnt_exp = zest_init_data.fcnt_exp;
    int8_t *phs_center = zest_init_data.phs_center;
    uint16_t tempC = UART_GETC( BASE_UART0 );
    int16_t dval;
    int32_t dval32;
    bool pass;
    size_t ix;

    if ( !UART_IS_DATA_OK( tempC ) ){
        return;
    }

    switch( tempC ){
        case 0x14:   // Ctrl+T
            printf("Rebooting...\n");
            __asm__ volatile ("J 0");
            break;

        case '?':
            printf("?    Help\n");
            printf("r    marble ina219, xadc\n");
            printf("t    zest ad7823, ad7794\n");
            printf("a    zest ad9653 ADC readings\n");
            printf("f    frequency and phase readings\n");
            printf("w    adc wfm test\n");
            printf("d    dac alignment\n");
            printf("l    llrf test\n");
            break;

        case 'r':
            print_marble_status();
            break;

        case 't':
            printf("---- Test Data: ----\n");
            // sync_zest_clocks();
            for (ix=0; ix<3; ix++) {
                pass = check_zest_freq(ix, fcnt_exp[ix]);
                printf("Freq %d Check: %s", ix, pass ? "PASS\n" : "FAIL\n");
            }
            read_amc7823_adcs();
            read_ad7794_adcs();
            break;

        case 'a':
            // sync_zest_clocks();
            for (ix=0; ix<8; ix++) {
                dval = read_zest_adc(ix);
                // printf("ADC chan %d hex : %#06x\n", ix, (uint16_t)dval);
                printf("ADC chan %d dout: %+4d\n", ix, dval);
            }
            break;

        case 'f':
            for (ix=0; ix<=3; ix++) {
                pass = check_zest_freq(ix, fcnt_exp[ix]);
                printf("Freq %d Check: %s", ix, pass ? "PASS\n" : "FAIL\n");
            }
            for (ix=0; ix<2; ix++) {
                align_adc_clk_phase(ix, phs_center[ix]);
            }
            check_div_clk_phase(2, 0);
            break;

        case 'w':
            test_adc_pn9(8);
            break;

        case 'd':
            // init_zest_dbg(BASE_ZEST, &zest_init_data);
            for (ix=6*16; ix<6*16+10; ix++) {  // read page 4
                // write_lb_reg(LB_MARBLE_SPI_MBOX + ix, 0x1234);
                dval32 = read_lb_reg(LB_MARBLE_SPI_MBOX + ix);
                printf("mbox[%u]: %x\n", ix, dval32);
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
            _putchar(tempC);
            return;
    }
}
