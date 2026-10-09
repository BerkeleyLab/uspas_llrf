// Design-specific firmware settings for alsu, included at the end of settings.h.
#ifndef _SETTINGS_DESIGN_H_
#define _SETTINGS_DESIGN_H_

// Modbus UART: rs485_uart on the SoC expansion port (top/alsu/design_mid.vh)
#define BASE_UART1             0x06000000
#define IRQ_UART1_RX           0x04          // ext_irq[0]

// connect modbus client to UART1
#define MODBUS_BASE_UART        BASE_UART1
#define MODBUS_IRQ_UART         IRQ_UART1_RX
#ifdef SIMULATION
    #define MODBUS_BAUDRATE     1000000
#else
    #define MODBUS_BAUDRATE     115200
#endif
// Need to accommodate the largest modbus packet
#define MODBUS_BUFFER_SIZE       (255)

// Debug defines
#define MB_MEMORY_ALLOW_ALL_WRITES (0)

// A necessary hack to disable blocking reads from the
// horrendously slow AD7794 and to allow timely response
// to modbus messages (or any other comms going through
// the picorv32).
#define ZEST_BYPASS_AD7794_READS

// Poll Modbus on every main-loop iteration instead of the 20 Hz loop
#define DESIGN_FAST_MAIN_LOOP

#endif
