// ALSU firmware hooks (soc/common/design_hooks.h): Modbus-RTU client on UART1
#include <stdint.h>
#include "settings.h"
#include "printf.h"
#include "uart.h"
#include "mb_client.h"
#include "init_modbus.h"
#include "design_hooks.h"

void design_init(void) {
    modbus_init();
    printf("==== Modbus Init       ==== : done.\n");
}

void design_irq(uint32_t irqs) {
    // Modbus byte received
    if (irqs & (1 << MODBUS_IRQ_UART)) {
        modbus_irq_rx(UART_GETC(MODBUS_BASE_UART));
    }
}

void design_poll(void) {
    modbusPoll();
    regmap_poll();
}

static void modbus_status(void) {
    uint32_t sr = GET_REG(MODBUS_BASE_UART + REG_UART_STATUS);
    uint16_t cc;
    printf("sr = %x", sr);
    if (sr & 2) {
        cc = UART_GETC(MODBUS_BASE_UART);
        printf("; cc = %c", cc);
    }
    printf("\r\n");
}

int design_console(char c) {
    switch (c) {
        case '?':
            printf("s    modbus status\n");
            return 1;
        case 's':
            modbus_status();
            return 1;
    }
    return 0;
}
