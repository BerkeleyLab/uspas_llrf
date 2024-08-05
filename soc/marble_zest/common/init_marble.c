#include "settings.h"
#include "marble.h"

const marble_dev_t marble = {
    .pca9555 = {
        {.i2c_mux_sel = I2C_SEL_APPL, .i2c_addr = I2C_ADR_PCA9555_QSFP},
        {.i2c_mux_sel = I2C_SEL_APPL, .i2c_addr = I2C_ADR_PCA9555_MISC}
    },
    .ina219 = {
        {.i2c_mux_sel = I2C_SEL_APPL, .i2c_addr = I2C_ADR_INA219_12V,  .rshunt_mOhm = 27, .current_lsb_uA = 100},
        {.i2c_mux_sel = I2C_SEL_APPL, .i2c_addr = I2C_ADR_INA219_FMC1, .rshunt_mOhm = 82, .current_lsb_uA = 10},
        {.i2c_mux_sel = I2C_SEL_APPL, .i2c_addr = I2C_ADR_INA219_FMC2, .rshunt_mOhm = 82, .current_lsb_uA = 10},
    },
    .qsfps = {
        {.module_present = false, .page_select = 0, .i2c_mux_sel=I2C_SEL_QSFP1, .i2c_addr=I2C_ADR_QSFP},
        {.module_present = false, .page_select = 0, .i2c_mux_sel=I2C_SEL_QSFP2, .i2c_addr=I2C_ADR_QSFP}
    },
    .adn4600 = {
        .i2c_mux_sel = I2C_SEL_CLK,
        .i2c_addr = I2C_ADR_ADN4600,
        // IP0-7: EXT0_CLK, EX1_CLK, FPGA_REF_CLK0, SI570_CLK, FMC1_GBTCLK0, FMC1_GBTCLK1, FMC2_GBTCLK0, FMC2_GBTCLK1
        // OP0-7: MGT_CLK_0, MGT_CLK_1, NC, NC, MGT_CLK_2, MGT_CLK_3, NC, NC
        .xpt_cfgs = {
            (2 << 4) | 0,   // FPGA_REF_CLK0    -> MGT_CLK_0 at OUT0
            (2 << 4) | 1,   // FPGA_REF_CLK0    -> MGT_CLK_1 at OUT1
            (2 << 4) | 4,   // FPGA_REF_CLK0    -> MGT_CLK_2 at OUT4
            (6 << 4) | 5,   // FMC2_GBTCLK0_M2C -> MGT_CLK_3 at OUT5
        }
    }
};
