#include <stdint.h>
#include "settings.h"
#include "printf.h"
#include "uart.h"
#include "i2c_soft.h"
#include "gpio.h"
#include "timer.h"
#include "system.h"
#include "localbus.h"
#include "marble.h"
#include "zest.h"
#include "xadc.h"
#include "llrf.h"
#include "evr_gtx_wrapper.h"
#ifdef SIMULATION
#include "llrf_regs_addr.h"
#endif

extern marble_init_t marble_init_data;
extern zest_init_t zest_init_data;
extern t_init_llrf_data llrf_init_data;

void _putchar( char c ){
    UART_PUTC( BASE_UART0, c );
}

void init(void) {
    UART_INIT( BASE_UART0, BOOTLOADER_BAUDRATE );       // Debug print (USB serial)
    // GPIO pin config
    SET_GPIO1( BASE_GPIO, GPIO_OE_REG, PIN_PCA9548_RST, 1 );// Drive PCA9548 RESET pin
    SET_GPIO8( BASE_GPIO, GPIO_OE_REG, 3, 0xFF );       // Drive LEDs
    i2c_init( PIN_I2C_SDA, PIN_I2C_SCL );
    // reset PCA9548
    SET_GPIO1( BASE_GPIO, GPIO_OUT_REG, PIN_PCA9548_RST, 0 );
    SET_GPIO1( BASE_GPIO, GPIO_OUT_REG, PIN_PCA9548_RST, 1 );
}

int main(void) {
    bool pass=true;
    init();
#ifdef SIMULATION
#ifdef XSIM_DBG  // top level
    // printf("# TOP SIM #\n");
    pass = init_zest_dbg(BASE_ZEST);
#else        // system_tb.v, faster
    printf("Simulating read XADC...:\n");
    uint32_t xadc_data;
    int temp;
    SET_SFR1(BASE_XADC + XADC_BASE2_SFR, 0, SFR_BIT_XADC_RESET, 1);
    xadc_data = GET_REG(BASE_XADC + (XADC_CHAN_TEMP<<2));
    temp = (xadc_data>>4) * 503.975 / 4096 - 273.15;
    printf("Temp reg: %#lx, %d degC\n", xadc_data, temp);
    pass &= (xadc_data == 0x9772);

    printf("Simulating LLRF init...:\n");
    pass &= init_llrf(&llrf_init_data);

    printf(pass ? "PASS\n":"FAIL\n");
#endif
    return 0;
#else   // not SIMULATION
    printf(" _   _ ____  ____   _    ____    _     _     ____  _____ \n");
    printf("| | | / ___||  _ \\ / \\  / ___|  | |   | |   |  _ \\|  ___|\n");
    printf("| | | \\___ \\| |_) / _ \\ \\___ \\  | |   | |   | |_) | |_   \n");
    printf("| |_| |___) |  __/ ___ \\ ___) | | |___| |___|  _ <|  _|  \n");
    printf(" \\___/|____/|_| /_/   \\_\\____/  |_____|_____|_| \\_\\_|    \n");

    debug_printf("=== VERBOSE MODE ===\n");
    printf("GIT_REV_ID: %x\n", (uint32_t)read_lb_reg(LB_GIT_REV_ID));

    pass &= init_marble(&marble_init_data);
    printf("==== Marble Init       ==== : %s.\n", pass?"PASS":"FAIL");
    pass &= init_zest(BASE_ZEST, &zest_init_data);
    printf("==== ZEST Init         ==== : %s.\n", pass?"PASS":"FAIL");
    pass &= init_llrf(&llrf_init_data);
    printf("==== LLRF Init         ==== : %s.\n", pass?"PASS":"FAIL");
    pass &= init_evr_gtx();
    printf("==== EVR Init          ==== : %s.\n", pass?"PASS":"FAIL");

    set_llrf_dac_permit(pass);
    set_llrf_bist_pass(pass);

    while(1) {
        handle_ui();
        check_gtx_align();
    }

#endif
}
