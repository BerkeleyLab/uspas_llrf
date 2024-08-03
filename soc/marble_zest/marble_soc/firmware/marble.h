#ifndef _MARBLE_H_
#define _MARBLE_H_
#include <stdint.h>
#include <stdbool.h>

typedef union _DataDword {
    uint32_t value;
    unsigned char bytes[4];
} DataDword;

typedef union _DataWord {
    uint16_t value;
    unsigned char bytes[2];
} DataWord;

typedef struct t_reg8 {
    uint8_t addr;
    uint8_t data;
} t_reg8;

typedef struct t_reg16 {
    uint16_t addr;
    uint16_t data;
} t_reg16;

typedef struct t_ina219_info {
    const uint8_t i2c_mux_sel;
    const uint8_t i2c_addr;
    const uint16_t rshunt_mOhm;
    const uint16_t current_lsb_uA;
    int16_t vshunt_uV;
    uint16_t vbus_mV;
    uint16_t power_uW;
    int32_t curr_uA;
} t_ina219_info;

typedef struct t_pca9555_info {
    const uint8_t i2c_mux_sel;
    const uint8_t i2c_addr;
    uint8_t i0_val;
    uint8_t i1_val;
} t_pca9555_info;

typedef struct t_adn4600_info {
    const uint8_t i2c_mux_sel;
    const uint8_t i2c_addr;
    const uint8_t xpt_cfgs[4];     // XPT Configuration for 4 outputs
} t_adn4600_info;

/**
 * @struct qsfp_status
 * @brief Structure holding the parameters for QSFP status SFF-8636
 */
typedef struct t_qsfp_info {
    bool module_present;
    /** I2C multiplexer channel */
    const uint8_t i2c_mux_sel;
    /** I2C device address */
    const uint8_t i2c_addr;
    /** Page Select Page 00, Byte 127*/
    uint8_t page_select;
    /** Latched Tx4-1 Rx3-1 LOS indicator, Page 00h Byte 3 */
    uint8_t chan_stat_los;
    /** Internally measured temperature, LSB 1/256 C. Page 00h Byte 22-23 */
    int16_t temperature;
    /** Internally measured voltage, LSB 0.1 mV. Page 00h Byte 26-27 */
    uint16_t voltage;
    /** Tx bias current, LSB 2 µA, Page 00h Byte 42-49 */
    uint16_t bias_current[4];
    /** Rx power, LSB 0.1 µW, Page 00h Byte 34-41 */
    uint16_t rx_power[4];    
    /** Tx power, LSB 0.1 µW, Page 00h Byte 50-57 */
    uint16_t tx_power[4];
    /** Page 00h Byte 148-163 */
	unsigned char vendor_name[16];
    /** Page 00h Byte 168-183 */
	unsigned char part_num[16];
    /** Page 00h Byte 196-211 */
	unsigned char serial_num[16];
} t_qsfp_info;

typedef struct t_marble_dev {
    t_ina219_info ina219[3];
    t_pca9555_info pca9555[2];
    t_qsfp_info qsfps[2];
    t_adn4600_info adn4600;
} t_marble_dev;

// i2c device address (7bit)
#define I2C_ADR_PCA9548        0x70
#define I2C_ADR_FMC1           0x50   // M24C02, GA0=0, GA1=0
#define I2C_ADR_FMC2           0x52   // M24C02, GA0=1, GA1=0
#define I2C_ADR_INA219_12V     0x42  // I2C_SEL_APPL: U57
#define I2C_ADR_INA219_FMC2    0x41  // I2C_SEL_APPL: U32
#define I2C_ADR_INA219_FMC1    0x40  // I2C_SEL_APPL: U17
#define I2C_ADR_PCA9555_QSFP   0x22  // I2C_SEL_APPL: U34
#define I2C_ADR_PCA9555_MISC   0x21  // I2C_SEL_APPL: U39
#define I2C_ADR_SI570          0x77  // I2C_SEL_APPL: Y6
#define I2C_ADR_ADN4600        0x48  // I2C_SEL_CLK:  U2
#define I2C_ADR_QSFP           0x50  // I2C_SEL_QSFP1 / I2C_SEL_QSFP2

// i2c multiplexer channels
#define I2C_SEL_FMC1     (1<<0)
#define I2C_SEL_FMC2     (1<<1)
#define I2C_SEL_CLK      (1<<2)
#define I2C_SEL_SDRAM    (1<<3)
#define I2C_SEL_QSFP1    (1<<4)
#define I2C_SEL_QSFP2    (1<<5)
#define I2C_SEL_APPL     (1<<6)

/**
 * @brief PCA9548: Set the channel mask register I2C multiplexer.
 * @param ch  -  channel to be selected, 0-7
 * @return true on success
 */
bool marble_i2c_mux_set(uint8_t ch);

/**
 * Scan I2C from 0-127
 */
void marble_i2c_scan(void);

/**
 * Poll QSFP status
 * @param qsfp_param qsfp status struct
 */
void get_qsfp_info(t_qsfp_info *qsfp_param);

/**
 * Poll 3 INA219 status
 * @param info pointer to t_ina219_info struct
 */
bool get_ina219_info(t_ina219_info *info);

/**
 * Poll 2 PCA9555 I0/I1 status
 * @param info pointer to t_pca9555_info struct
 */
bool get_pca9555_info(t_pca9555_info *info);

/**
 * Poll marble board device info including ina219, pca9555, qsfp
 * @param marble pointer to t_marble_dev structure
 */
bool get_marble_info(t_marble_dev *marble);

/**
 * Initialize Marble board by programming i2c devices
 * including pca9555 and clock settings;
 * Poll all device information into marble_dev;
 * @param marble pointer to t_marble_dev structure
 */
bool init_marble(t_marble_dev *marble);

/**
 * Print marble dev information after get_marble_info()
 * @param marble pointer to t_marble_dev structure
 */
void print_marble_status(const t_marble_dev *marble);
#endif
