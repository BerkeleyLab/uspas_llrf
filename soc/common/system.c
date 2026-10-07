#include <stdint.h>
#include "settings.h"
#include "irqs.h"
#include "printf.h"
#include "uart.h"
#include "i2c_soft.h"
#include "gpio.h"
#include "timer.h"
#include "system.h"
#include "localbus.h"
#include "marble.h"
#include "zest.h"
#include "marble_regs_addr.h"
#include "xadc.h"
#include "llrf.h"
#include "evr_gt_wrapper.h"
#include "string.h"
#ifdef SIMULATION
#include "llrf_regs_addr.h"
#endif

extern marble_init_t marble_init_data;
extern zest_init_t zest_init_data;
extern init_llrf_data_t llrf_init_data;
extern marble_dev_t marble;
extern zest_status_t zest;

void _putchar(char c){
    UART_PUTC( BASE_UART0, c );
}

volatile char last_char=0;
uint32_t *irq(uint32_t *regs, uint32_t irqs)
{
    if (irqs & (1 << IRQ_UART0_RX)) {
        // Ctrl + T = reset
        last_char = UART_GETC(BASE_UART0);
        if (last_char == 0x14) {
            _picorv32_irq_reset();
        }
    }
    return regs;
}

void memcpy_lb_dma(uint32_t base, unsigned char *buffer, size_t len) {
    for (size_t ix=0; ix<len; ix++) {
        write_lb_reg(base + ix, *buffer++);
    }
}

void init(void) {
    UART_INIT( BASE_UART0, BOOTLOADER_BAUDRATE );       // Debug print (USB serial)
    _picorv32_irq_enable(1 << IRQ_UART0_RX);
    // GPIO pin config
    SET_GPIO1( BASE_GPIO, GPIO_OE_REG, GPIO_PIN_PCA9548_RST, 1 );
    SET_GPIO8( BASE_GPIO, GPIO_OE_REG, GPIO_BYTE_TRIG_INP_SEL, 0x1F );
    SET_GPIO8( BASE_GPIO, GPIO_OE_REG, GPIO_BYTE_TRIG_OUT_SEL, 0xFF );
    i2c_init( GPIO_PIN_I2C_SDA, GPIO_PIN_I2C_SCL );
    // reset PCA9548
    SET_GPIO1( BASE_GPIO, GPIO_OUT_REG, GPIO_PIN_PCA9548_RST, 0 );
    SET_GPIO1( BASE_GPIO, GPIO_OUT_REG, GPIO_PIN_PCA9548_RST, 1 );

#ifndef SIMULATION
    if (strcmp(USPAS_LLRF_FSET, "AWA") == 0) {
        // enable 2 up converters in chassis
        SET_GPIO1( BASE_GPIO, GPIO_OE_REG, GPIO_PIN_EN_UPCONV_0, 1 );
        SET_GPIO1( BASE_GPIO, GPIO_OE_REG, GPIO_PIN_EN_UPCONV_1, 1 );
        SET_GPIO1( BASE_GPIO, GPIO_OUT_REG, GPIO_PIN_EN_UPCONV_0, 1 );
        SET_GPIO1( BASE_GPIO, GPIO_OUT_REG, GPIO_PIN_EN_UPCONV_1, 1 );

        // Select ZEST_PMOD2 (J18) pin 1 as external trigger
        SET_GPIO8( BASE_GPIO, GPIO_OUT_REG, GPIO_BYTE_TRIG_INP_SEL, 25 );
    }
    else if (strcmp(USPAS_LLRF_FSET, "USPAS") == 0) {
        // Select Marble_PMOD1 (J12) pin 0 as external trigger input
        SET_GPIO8( BASE_GPIO, GPIO_OUT_REG, GPIO_BYTE_TRIG_INP_SEL, 0 );
        // Select Marble_PMOD1 (J12) pin 1 as internal trigger output
        SET_GPIO8( BASE_GPIO, GPIO_OUT_REG, GPIO_BYTE_TRIG_OUT_SEL, 0b10 );
    }
#endif
}

int main(void) {
    bool pass=true;
    init();
#ifdef SIMULATION
#ifdef XSIM_DBG  // top_sim
    pass = init_zest_dbg(BASE_ZEST);
#else        // system_tb.v, faster
    uint32_t xadc_data;
    int temp;
    // PMOD3[1] as trigger input
    SET_GPIO8( BASE_GPIO, GPIO_OUT_REG, GPIO_BYTE_TRIG_INP_SEL, 25 );
    // PMOD0[1] as trigger output
    SET_GPIO8( BASE_GPIO, GPIO_OUT_REG, GPIO_BYTE_TRIG_OUT_SEL, 0b10 );

    SET_SFR1(BASE_XADC + XADC_BASE2_SFR, 0, SFR_BIT_XADC_RESET, 1);
    xadc_data = GET_REG(BASE_XADC + (XADC_CHAN_TEMP<<2));
    temp = (xadc_data>>4) * 503.975 / 4096 - 273.15;
    printf("Simulating read XADC...:\n");
    printf("Temp reg: %#lx, %d degC\n", xadc_data, temp);
    pass &= xadc_data == 0x9772;

    printf("Simulating LLRF init...:\n");
    pass &= init_llrf(&llrf_init_data);
#endif  // #ifdef XSIM_DBG
    printf(pass ? "PASS\n":"FAIL\n");
#else   // #ifdef SIMULATION
    printf(" _   _ ____  ____   _    ____    _     _     ____  _____ \n");
    printf("| | | / ___||  _ \\ / \\  / ___|  | |   | |   |  _ \\|  ___|\n");
    printf("| | | \\___ \\| |_) / _ \\ \\___ \\  | |   | |   | |_) | |_   \n");
    printf("| |_| |___) |  __/ ___ \\ ___) | | |___| |___|  _ <|  _|  \n");
    printf(" \\___/|____/|_| /_/   \\_\\____/  |_____|_____|_| \\_\\_|    \n");

    debug_printf("=== VERBOSE MODE ===\n");
    printf("FSET: %s\n", USPAS_LLRF_FSET);
    printf("GIT_REV_ID: %x\n", (uint32_t)read_lb_reg(LB_GIT_REV_ID));

    pass &= init_marble(&marble_init_data);
    printf("==== Marble Init       ==== : %s.\n", pass?"PASS":"FAIL");
    pass &= init_zest(BASE_ZEST, &zest_init_data);
    printf("==== ZEST Init         ==== : %s.\n", pass?"PASS":"FAIL");
    pass &= init_llrf(&llrf_init_data);
    printf("==== LLRF Init         ==== : %s.\n", pass?"PASS":"FAIL");
    if (marble_init_data.enable_evr_gt) {
        pass &= init_evr_gt();
        printf("==== EVR Init          ==== : %s.\n", pass?"PASS":"FAIL");
    }

    set_llrf_soft_drive_enable(pass);
    set_llrf_bist_pass(pass);

    unsigned cnt=0;
    while(1) {
        if (last_char) {
            console(last_char);
        }
        last_char = 0;

        // 20 Hz cycle time
        DELAY_US(50000);
        cnt++;
        if (cnt % 20 == 0) {    // update rate 1 Hz
            if (marble_init_data.enable_poll_status) {
                get_marble_info(&marble);
                memcpy_lb_dma(BSP_INFO_BUF, (unsigned char *)&marble, sizeof(marble));
            }
            if (zest_init_data.enable_poll_status) {
                get_zest_status(&zest);
                memcpy_lb_dma(BSP_INFO_BUF+sizeof(marble), (unsigned char *)&zest, sizeof(zest));
            }
        }
    }

#endif   // #ifdef SIMULATION
    return 0;
}
