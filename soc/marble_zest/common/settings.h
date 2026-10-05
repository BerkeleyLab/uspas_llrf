#ifndef _SETTINGS_H_
#define _SETTINGS_H_
/* ----------------------------- */
/*  Global settings file */
/* ----------------------------- */

// Base addresses of Peripherals
#define BASE_GPIO              0x01000000
#define BASE_UART0             0x02000000    // Debug UART
#define BASE_LOCALBUS          0x03000000    // Localbus Bridge
#define BASE_XADC              0x04000000
#define BASE_ZEST              0x05000000    // zest if
#define BASE_I2C               BASE_GPIO
#define BASE_UART1             0x06000000    // Modbus UART

#define IRQ_UART0_RX           0x03
#define IRQ_UART1_RX           0x04

#define F_CLK                  125000000     // [Hz]

#define BOOTLOADER_DELAY    (F_CLK/1000)     // How long to wait in the bootloader

#ifndef BOOTLOADER_BAUDRATE
#define BOOTLOADER_BAUDRATE 115200
#endif

#define I2C_DELAY_US            3            //~half a clock period [us]

// GPIO PIN assignments (must match system.v)
#define GPIO_PIN_I2C_SDA             0
#define GPIO_PIN_I2C_SCL             1
#define GPIO_PIN_PCA9548_RST         2
#define GPIO_PIN_EN_UPCONV_0         3
#define GPIO_PIN_EN_UPCONV_1         4

#define GPIO_BYTE_TRIG_INP_SEL       1
#define GPIO_BYTE_TRIG_OUT_SEL       2

// LOCALBUS register address:
//   marble_zest_top.json:
#define LB_GIT_REV_ID         0x0

#ifndef USPAS_LLRF_FSET
#define USPAS_LLRF_FSET       "USPAS"
#endif

#define DEBUG_PRINT 0
#define debug_printf(...) \
        do { if (DEBUG_PRINT) printf(__VA_ARGS__); } while (0)

#define ARRAY_SIZE(arr) ((sizeof arr) / (sizeof arr[0]))

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

#endif
