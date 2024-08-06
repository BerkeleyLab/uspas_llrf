#include <stdbool.h>
#include "i2c_soft.h"
#include "sfr.h"
#include "xadc.h"
#include "settings.h"
#include "print.h"
#ifdef NONSTD_PRINTF
    #include "printf.h"
#else
    #include <stdio.h>
#endif
#include "marble.h"

marble_dev_t marble = {
    .variant = MARBLE_VAR_MARBLE_V1_4,
    .pca9555_qsfp ={.i2c_mux_sel=I2C_SEL_APPL, .i2c_addr=I2C_ADR_PCA9555_QSFP},
    .pca9555_misc ={.i2c_mux_sel=I2C_SEL_APPL, .i2c_addr=I2C_ADR_PCA9555_MISC},
    .ina219_12v = {
        .i2c_mux_sel=I2C_SEL_APPL, .i2c_addr=I2C_ADR_INA219_12V,
        .rshunt_mOhm=27, .current_lsb_uA=100},
    .ina219_fmc1 = {
        .i2c_mux_sel=I2C_SEL_APPL, .i2c_addr=I2C_ADR_INA219_FMC1,
        .rshunt_mOhm=82, .current_lsb_uA=10},
    .ina219_fmc2 = {
        .i2c_mux_sel=I2C_SEL_APPL, .i2c_addr=I2C_ADR_INA219_FMC2,
        .rshunt_mOhm=82, .current_lsb_uA=10},
    .qsfp1 = {
        .module_present=false, .page_select=0,
        .i2c_mux_sel=I2C_SEL_QSFP1, .i2c_addr=I2C_ADR_QSFP},
    .qsfp2 = {
        .module_present=false, .page_select=0,
        .i2c_mux_sel=I2C_SEL_QSFP2, .i2c_addr=I2C_ADR_QSFP},
    .adn4600 = {.i2c_mux_sel=I2C_SEL_CLK, .i2c_addr=I2C_ADR_ADN4600},
    .si570 = {.i2c_mux_sel=I2C_SEL_APPL, .i2c_addr=I2C_ADR_SI570_270}
};

static bool marble_i2c_write(uint8_t i2c_addr, uint8_t reg_addr, const uint8_t *data, uint16_t len) {
    return i2c_write_regs(i2c_addr, reg_addr, data, len);
}

static bool marble_i2c_read(uint8_t i2c_addr, uint8_t reg_addr, uint8_t *data, uint16_t len) {
    return i2c_read_regs(i2c_addr, reg_addr, data, len);
}

bool marble_i2c_mux_set( uint8_t ch ) {
    return i2c_write_regs(I2C_ADR_PCA9548, ch, 0, 0);
}

static uint16_t reorder_bytes(uint16_t a) {
	uint16_t ret = ((a >> 8) & 0xff) | ((a & 0xff) << 8);
	return ret;
}

bool i2c_write_word(uint8_t i2c_addr, uint8_t reg_addr, uint16_t reg) {
    bool ret = true;
    DataWord data;
    data.value = reorder_bytes(reg);

    ret &= i2c_write_regs(i2c_addr, reg_addr, &data.bytes[0], 2);
    return ret;
}

bool i2c_read_word(uint8_t i2c_addr, uint8_t reg_addr, uint16_t *reg) {
    bool ret = true;
    DataWord rdata;

    ret &= i2c_read_regs(i2c_addr, reg_addr, &rdata.bytes[0], 2);
    *reg = reorder_bytes(rdata.value);
    return ret;
}

bool i2c_write_regmap_byte(uint8_t i2c_addr, t_reg8 *regmap, size_t len) {
    bool ret = true;
    while ( len-- > 0 ){
        ret &= i2c_write_regs(i2c_addr, regmap->addr, &(regmap->data), 1);
        regmap++;
    }
    return ret;
}

bool i2c_write_regmap_word(uint8_t i2c_addr, t_reg16 *regmap, size_t len) {
    bool ret = true;
    while ( len-- > 0 ){
        ret &= i2c_write_word(i2c_addr, regmap->addr, regmap->data);
        regmap++;
    }
    return ret;
}

void get_qsfp_info(qsfp_info_t *qsfp_param) {
    unsigned short i=0;
    unsigned char buf[8];

    marble_i2c_mux_set(qsfp_param->i2c_mux_sel);
   /* Map upper memory page 00h to bytes 128-255*/
    marble_i2c_write(qsfp_param->i2c_addr, 127, &qsfp_param->page_select, 1);

    marble_i2c_read(qsfp_param->i2c_addr, 148, qsfp_param->vendor_name, 16);
    marble_i2c_read(qsfp_param->i2c_addr, 168, qsfp_param->part_num, 16);
    marble_i2c_read(qsfp_param->i2c_addr, 196, qsfp_param->serial_num, 16);

    marble_i2c_read(qsfp_param->i2c_addr, 3, &qsfp_param->chan_stat_los, 1);
    marble_i2c_read(qsfp_param->i2c_addr, 22, buf, 2);
    qsfp_param->temperature = (uint16_t)(buf[0] << 8 | buf[1]) >> 8;  // C
    marble_i2c_read(qsfp_param->i2c_addr, 26, buf, 2);
    qsfp_param->voltage = (int16_t)(buf[0] << 8 | buf[1]) / 10;  // mV
    marble_i2c_read(qsfp_param->i2c_addr, 42, buf, 8);
    for (i=0; i < 4; i++) {
        qsfp_param->bias_current[i] = (int16_t)(buf[2*i] << 8 | buf[2*i+1]) * 2;  // µA
    }
    marble_i2c_read(qsfp_param->i2c_addr, 50, buf, 8);
    for (i=0; i < 4; i++) {
        qsfp_param->tx_power[i] = (int16_t)(buf[2*i] << 8 | buf[2*i+1]) / 10; // µW
    }
    marble_i2c_read(qsfp_param->i2c_addr, 34, buf, 8);
    for (i=0; i < 4; i++) {
        qsfp_param->rx_power[i] = (int16_t)(buf[2*i] << 8 | buf[2*i+1]) / 10; // µW
    }
}

bool get_ina219_info(ina219_info_t *info) {
    bool ret = true;
    uint16_t regs[5];
    ret &= marble_i2c_mux_set(info->i2c_mux_sel);

    for (size_t i=0; i<5; i++) {
        ret &= i2c_read_word(info->i2c_addr, i, regs+i);
    }

    info->vshunt_uV = (int16_t)regs[1] * 100;
    info->vbus_mV = (regs[2] >> 3) * 4;
    info->power_uW = regs[3] * info->current_lsb_uA * 20;  // eqn (3)
    info->curr_uA = (int16_t)regs[4] * info->current_lsb_uA;
    return ret;
}

bool get_pca9555_info(pca9555_info_t *info) {
    bool ret = true;
    ret &= marble_i2c_mux_set(info->i2c_mux_sel);

    ret &= marble_i2c_read(info->i2c_addr, 0, &(info->i0_val), 1);
    ret &= marble_i2c_read(info->i2c_addr, 1, &(info->i1_val), 1);
    return ret;
}

bool get_adn4600_info(adn4600_info_t *info) {
    bool ret = true;
    ret &= marble_i2c_mux_set(info->i2c_mux_sel);
    for (unsigned ix=0; ix<8; ix++) {
        ret &= marble_i2c_read(info->i2c_addr, 0x50+ix, &info->xpt_status[ix], 1);
    }
    return ret;
}

bool set_ina219_info(ina219_info_t *info, marble_init_word_t *p_data) {
    bool ret = true;
    ret &= marble_i2c_mux_set(info->i2c_mux_sel);
    ret &= i2c_write_regmap_word(
            info->i2c_addr, p_data->regmap, p_data->len);
    return ret;
}

bool set_pca9555_info(pca9555_info_t *info, marble_init_byte_t *p_data) {
    bool ret = true;
    ret &= marble_i2c_mux_set(info->i2c_mux_sel);
    ret &= i2c_write_regmap_byte(
            info->i2c_addr, p_data->regmap, p_data->len);
    return ret;
}

bool set_adn4600_info(adn4600_info_t *info, marble_init_byte_t *p_data) {
    bool ret = true;
    ret &= marble_i2c_mux_set(info->i2c_mux_sel);
    ret &= i2c_write_regmap_byte(
        info->i2c_addr, p_data->regmap, p_data->len);
    return ret;
}

bool get_marble_info(marble_dev_t *marble) {
    bool ret = true;

    ret &= get_adn4600_info(&marble->adn4600);
    ret &= get_ina219_info(&marble->ina219_12v);
    ret &= get_ina219_info(&marble->ina219_fmc1);
    ret &= get_ina219_info(&marble->ina219_fmc2);
    ret &= get_pca9555_info(&marble->pca9555_qsfp);
    ret &= get_pca9555_info(&marble->pca9555_misc);
    marble->qsfp1.module_present = (marble->pca9555_qsfp.i0_val & 0x20) == 0;
    marble->qsfp2.module_present = (marble->pca9555_qsfp.i1_val & 0x20) == 0;
    if (marble->qsfp1.module_present) {
        get_qsfp_info(&marble->qsfp1);
    }
    if (marble->qsfp2.module_present) {
        get_qsfp_info(&marble->qsfp2);
    }

    return ret;
}

void print_marble_status(void) {
    ina219_info_t ina219[3] = {marble.ina219_fmc1, marble.ina219_fmc2, marble.ina219_12v};
    pca9555_info_t pca9555[2] = {marble.pca9555_qsfp, marble.pca9555_misc};
    qsfp_info_t qsfp[2] = {marble.qsfp1, marble.qsfp2};

    for (unsigned ix=0; ix<8; ix++) {
        printf(" %s: ADN4600: IN%1u -> OUT%1u\n", __func__, marble.adn4600.xpt_status[ix], ix);
    }

    for (unsigned i=0; i<3; i++) {
        printf(" %s: INA219 %1u:\n", __func__, i+1);
        printf(" %s: Vshunt:  %12d mV\n",  __func__, ina219[i].vshunt_uV / 1000);
        printf(" %s: Power:   %12d mW\n",  __func__, ina219[i].power_uW / 1000);
        printf(" %s: Vbus:    %12d mV\n",  __func__, ina219[i].vbus_mV);
        printf(" %s: Current: %12ld mA\n", __func__, ina219[i].curr_uA / 1000);
    }
    for (unsigned i=0; i<2; i++) {
        printf(" %s: PCA9555 %1u:\n",  __func__, i+1);
        printf(" %s: I0:      %#12X\n",__func__,  pca9555[i].i0_val);
        printf(" %s: I1:      %#12X\n",__func__,  pca9555[i].i1_val);
    }
    for (unsigned i=0; i<2; i++) {
        if (qsfp[i].module_present) {
            printf(" %s: QSFP%1u Vendor  :   %.16s\n",  __func__, i+1, qsfp[i].vendor_name);
            printf(" %s: QSFP%1u Part    :   %.16s\n",  __func__, i+1, qsfp[i].part_num);
            printf(" %s: QSFP%1u Serial  :   %.16s\n",  __func__, i+1, qsfp[i].serial_num);
            printf(" %s: QSFP%1u TXRX_LOS:   %#8X\n",   __func__, i+1, qsfp[i].chan_stat_los);
            printf(" %s: QSFP%1u Temp    :   %8d C\n",  __func__, i+1, qsfp[i].temperature);
            printf(" %s: QSFP%1u Volt    :   %8d mV\n", __func__, i+1, qsfp[i].voltage);
            for (unsigned j=0; j < 4; j++) {
                printf(" %s: QSFP%1u TxBias %u:   %8d µA\n", __func__,
                        i+1, j, qsfp[i].bias_current[j]);
                printf(" %s: QSFP%1u TxPwr  %u:   %8d µW\n", __func__,
                        i+1, j, qsfp[i].tx_power[j]);
                printf(" %s: QSFP%1u RxPwr  %d:   %8u µW\n", __func__,
                        i+1, j, qsfp[i].rx_power[j]);
            }
        }
    }
}

bool init_marble(marble_init_t *init_data)
{
    bool p = true;
    bool pass = true;

    printf("--===========  Marble Init  =============--\n");

    if (marble.variant == MARBLE_VAR_MARBLE_V1_4) {
        marble.si570.i2c_addr = I2C_ADR_SI570_270;
    } else {
        marble.si570.i2c_addr = I2C_ADR_SI570_125;
    }

    p = set_ina219_info(&marble.ina219_fmc1, &init_data->ina219_fmc1_data);  pass &= p;
    p = set_ina219_info(&marble.ina219_fmc2, &init_data->ina219_fmc2_data);  pass &= p;
    p = set_ina219_info(&marble.ina219_12v, &init_data->ina219_12v_data);  pass &= p;
    printf("==== INA219 init  ====  : %s.\n", p?"PASS":"FAIL");

    p = set_pca9555_info(&marble.pca9555_qsfp, &init_data->pca9555_qsfp_data);  pass &= p;
    p = set_pca9555_info(&marble.pca9555_misc, &init_data->pca9555_misc_data);  pass &= p;
    printf("==== PCA9555 init ====  : %s.\n", p?"PASS":"FAIL");

    p = set_adn4600_info(&marble.adn4600, &init_data->adn4600_data); pass &= p;
    printf("==== ADN4600 init ====  : %s.\n", p?"PASS":"FAIL");

    pass &= get_marble_info(&marble);
    print_marble_status();
    return pass;
}
