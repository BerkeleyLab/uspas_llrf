#ifndef SETTINGS_H
#define SETTINGS_H
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

#define F_CLK                  125000000     // [Hz]

#define BOOTLOADER_DELAY    (F_CLK/1000)     // How long to wait in the bootloader

// GPIO PIN assignments (must match top.v)
#define PIN_I2C_SDA             0
#define PIN_I2C_SCL             1
#define PIN_PCA9548_RST         2
#define I2C_DELAY_US            3            //~half a clock period [us]

// LOCALBUS registers:
// marble_bsp.json:
#define GT_RXRESET             0x40000
#define GTX_CPLL_RESET         0x40001
#define GTX_RX_PMARESET        0x40002
#define GTX_RX_SLIDE_REQ       0x40003
#define GTX_SOFT_RESET         0x40004
#define LB_MARBLE_SPI_MBOX     0x41000
#define GTX_RX_CLK_FREQUENCY   0x42002
#define GTX_REFCLK_FREQUENCY   0x42003
#define GTX_RX_RESETDONE       0x42004
#define GTX_RX_ALIGNED         0x42005
#define GTX_CPLL_LOCKED        0x42006
#define GTX_RX_NOTINTABLE      0x42007
#define US_SINCE_BOOT          0x42008
// marble_zest_top.json:
#define LB_GIT_REV_ID          0x0

#define DEBUG_PRINT 0
#define debug_printf(...) \
        do { if (DEBUG_PRINT) printf(__VA_ARGS__); } while (0)

#define ARRAY_SIZE(arr) ((sizeof arr) / (sizeof arr[0]))

#endif
