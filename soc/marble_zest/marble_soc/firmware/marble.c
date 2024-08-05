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

extern struct marble_dev_t marble;

static bool marble_i2c_write(uint8_t i2c_addr, uint8_t reg_addr, const uint8_t *data, uint16_t len)
{
    return i2c_write_regs(i2c_addr, reg_addr, data, len);
}

static bool marble_i2c_read(uint8_t i2c_addr, uint8_t reg_addr, uint8_t *data, uint16_t len)
{
    return i2c_read_regs(i2c_addr, reg_addr, data, len);
}

bool marble_i2c_mux_set( uint8_t ch ){
    return i2c_write_regs(I2C_ADR_PCA9548, ch, 0, 0);
}

static uint16_t reorder_bytes(uint16_t a)
{
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

void get_qsfp_info(qsfp_info_t *qsfp_param)
{
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

static bool marble_clk_init(const marble_dev_t *marble)
{
    bool ret = true;
    // 500mV output swing to satisify DS182 table 55
    t_reg8 config_regmap[] = {
        {0xc0, 0x20},   // TX0
        {0xc1, 0x40},
        {0xc2, 0xd5},
        {0xc8, 0x20},   // TX1
        {0xc9, 0x40},
        {0xca, 0xd5},
        {0xd0, 0},      // TX2
        {0xd8, 0},      // TX3
        {0xe0, 0x20},   // TX4
        {0xe1, 0x40},
        {0xe2, 0xd5},
        {0xe8, 0x20},   // TX5
        {0xe9, 0x40},
        {0xea, 0xd5},
        {0xf0, 0},      // TX6
        {0xf8, 0},      // TX7
    };
    uint8_t buf=1;

    ret &= marble_i2c_mux_set(marble->adn4600.i2c_mux_sel);

    // Static configurations, disable unused channels
    ret &= i2c_write_regmap_byte(
            marble->adn4600.i2c_addr, config_regmap,
            sizeof(config_regmap) / sizeof(config_regmap[0]));

    // Configure XPT (first bank of latches)
    for (unsigned ix=0; ix < sizeof marble->adn4600.xpt_cfgs / sizeof marble->adn4600.xpt_cfgs[0]; ix++) {
        ret &= marble_i2c_write(
            marble->adn4600.i2c_addr, 0x40, marble->adn4600.xpt_cfgs+ix, 1);
    }

    // Update XPT (second bank of latches, output connections programmed simultaneously)
    ret &= marble_i2c_write(marble->adn4600.i2c_addr, 0x41, &buf, 1);

    // Readback status
    for (unsigned ix=0; ix<8; ix++) {
        ret &= marble_i2c_read(marble->adn4600.i2c_addr, 0x50+ix, &buf, 1);
        printf(" %s: ADN4600 %#02x: IN%1d -> OUT%1d\n", __func__, 0x50+ix, buf, ix);
    }
    return ret;
}

static bool init_i2c_app_dev(void) {
    bool ret = true;

    ret &= marble_i2c_mux_set(I2C_SEL_APPL);

    // ----------------------------- INA219 -----------------------------
    // VBUS_MAX = 12V
    // VSHUNT_MAX = 0.08    (PGA = /8, +-320mV @ config=0x399f)
    // RSHUNT = 0.082
    // CurrentLSB = 1e-5 A (10uA per bit)
    //   Cal = trunc (0.04096 / (CurrentLSB * RSHUNT)) = 49950 (0xc31e)
    t_reg16 ina219_regmap[] = {
        {0, 0x399f},
        {5, 0xc31e}
    };
    ret &= i2c_write_regmap_word(
            I2C_ADR_INA219_FMC1, ina219_regmap,
            sizeof(ina219_regmap) / sizeof(ina219_regmap[0]));
    ret &= i2c_write_regmap_word(
            I2C_ADR_INA219_FMC2, ina219_regmap,
            sizeof(ina219_regmap) / sizeof(ina219_regmap[0]));

    // RSHUNT = 0.082 / 3 for I2C_ADR_INA219_12V
    // CurrentLSB = 1e-4 A (100uA per bit)
    // hex(int(0.04096 / (0.082 / 3 * 1e-4))) = 0x3a88
    ina219_regmap[1] = (t_reg16){5, 0x3a88};
    ret &= i2c_write_regmap_word(
            I2C_ADR_INA219_12V, ina219_regmap,
            sizeof(ina219_regmap) / sizeof(ina219_regmap[0]));

    // ----------------------------- PCA9555 -----------------------------
    // U34
    // P0[7:3] = [QSFP1_MOD_SELB, QSFP1_RSTB, QSFP1_MOD_PRS, QSFP1_LPMODE]
    // P1[7:3] = [QSFP2_MOD_SELB, QSFP2_RSTB, QSFP2_MOD_PRS, QSFP2_LPMODE]
    t_reg8 pca9555_u34_regmap[] = {
        {2, 0x48},  // Output: assert LPMODE, RSTB, dissert MOD_SELB on QSFP1
        {3, 0x48},  // Output: assert LPMODE, RSTB, dissert MOD_SELB on QSFP2
        {4, 0},
        {5, 0},
        {6, 0x37},  // Config: enable output on RST, LPMODE, MOD_SEL on QSFP1
        {7, 0x37}   // Config: enable output on RST, LPMODE, MOD_SEL on QSFP2
    };
    // U39
    // P0[7:4] = CFG_WP_B, THERM, FANFAIL, ALERT
    // P0[3:0] = EN_CON_JTAG, EN_USB_JTAG, NC, SI570_OE
    // P1[7:4] = CLKMUX_RST, NC, NC, NC,
    // P1[3:0] = LD13, LD14, NC, NC
    t_reg8 pca9555_u39_regmap[] = {
        {2, 0xfe},  // Output: Disable SI570
        {3, 0x80},  // LED on, do not reset ADN4600
        {4, 0},
        {5, 0},
        {6, 0xfe},  // Config: low for enabling output (only for Si570)
        {7, 0x73}
    };

    ret &= i2c_write_regmap_byte(
            I2C_ADR_PCA9555_QSFP, pca9555_u34_regmap,
            sizeof(pca9555_u34_regmap) / sizeof(pca9555_u34_regmap[0]));
    ret &= i2c_write_regmap_byte(
            I2C_ADR_PCA9555_MISC, pca9555_u39_regmap,
            sizeof(pca9555_u39_regmap) / sizeof(pca9555_u39_regmap[0]));

    return ret;
}

bool init_marble(marble_dev_t *marble)
{
    bool ret = true;

    printf("--===========  Marble Init  =============--\n");

    printf(" %s: === Switching to APP: ===\n", __func__);
    ret &= init_i2c_app_dev();
    printf(" %s: %24s\n", __func__, ret ? "PASS": "FAIL");

    printf(" %s: === Switching to CLK: ===\n", __func__);
    ret &= marble_clk_init(marble);
    printf(" %s: %24s\n", __func__, ret ? "PASS": "FAIL");

    // printf(" %s: === Switching to FMC1:  ===\n", __func__);
    // ret &= marble_i2c_mux_set(I2C_SEL_FMC1);

    // printf(" %s: === Switching to FMC2:  ===\n", __func__);
    // ret &= marble_i2c_mux_set(I2C_SEL_FMC2);

    ret &= get_marble_info(marble);
    print_marble_status(marble);
    printf(" %s: %24s\n", __func__, ret ? "PASS": "FAIL");

    printf(" %s: === Marble Init Done ===\n", __func__);

    return ret;
}

bool get_ina219_info(ina219_info_t *info) {
    bool ret = true;
    uint16_t regs[5];
    marble_i2c_mux_set(info->i2c_mux_sel);

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
    marble_i2c_mux_set(info->i2c_mux_sel);

    ret &= marble_i2c_read(info->i2c_addr, 0, &(info->i0_val), 1);
    ret &= marble_i2c_read(info->i2c_addr, 1, &(info->i1_val), 1);
    return ret;
}

bool get_marble_info(marble_dev_t *marble) {
    bool ret = true;

    ret &= get_ina219_info(&marble->ina219[0]);
    ret &= get_ina219_info(&marble->ina219[1]);
    ret &= get_ina219_info(&marble->ina219[2]);
    ret &= get_pca9555_info(&marble->pca9555[0]);
    ret &= get_pca9555_info(&marble->pca9555[1]);
    marble->qsfps[0].module_present = (marble->pca9555[0].i0_val & 0x20) == 0;
    marble->qsfps[1].module_present = (marble->pca9555[0].i1_val & 0x20) == 0;
    for (unsigned i=0; i<2; i++) {
        if (marble->qsfps[i].module_present) {
            get_qsfp_info(&marble->qsfps[i]);
        }
    }
    return ret;
}

void print_marble_status(const marble_dev_t *marble) {
    for (unsigned i=0; i<3; i++) {
        printf(" %s: INA219 %1d:\n", __func__, i+1);
        printf(" %s: Vshunt:  %8d mV\n",  __func__, marble->ina219[i].vshunt_uV / 1000);
        printf(" %s: Power:   %8d mW\n",  __func__, marble->ina219[i].power_uW / 1000);
        printf(" %s: Vbus:    %8d mV\n",  __func__, marble->ina219[i].vbus_mV);
        printf(" %s: Current: %8ld mA\n", __func__, marble->ina219[i].curr_uA / 1000);
    }
    for (unsigned i=0; i<2; i++) {
        printf(" %s: PCA9555 %1d:\n",  __func__, i+1);
        printf(" %s: I0:      %#8X\n",__func__,  marble->pca9555[i].i0_val);
        printf(" %s: I1:      %#8X\n",__func__,  marble->pca9555[i].i1_val);
    }
    for (unsigned i=0; i<2; i++) {
        if (marble->qsfps[i].module_present) {
            printf(" %s: QSFP%1d Vendor  :   %.16s\n",  __func__, i+1, marble->qsfps[i].vendor_name);
            printf(" %s: QSFP%1d Part    :   %.16s\n",  __func__, i+1, marble->qsfps[i].part_num);
            printf(" %s: QSFP%1d Serial  :   %.16s\n",  __func__, i+1, marble->qsfps[i].serial_num);
            printf(" %s: QSFP%1d TXRX_LOS:   %#8X\n",   __func__, i+1, marble->qsfps[i].chan_stat_los);
            printf(" %s: QSFP%1d Temp    :   %8d C\n",  __func__, i+1, marble->qsfps[i].temperature);
            printf(" %s: QSFP%1d Volt    :   %8d mV\n", __func__, i+1, marble->qsfps[i].voltage);
            for (unsigned j=0; j < 4; j++) {
                printf(" %s: QSFP%1d TxBias %d:   %8d µA\n", __func__,
                        i+1, j, marble->qsfps[i].bias_current[j]);
                printf(" %s: QSFP%1d TxPwr  %d:   %8d µW\n", __func__,
                        i+1, j, marble->qsfps[i].tx_power[j]);
                printf(" %s: QSFP%1d RxPwr  %d:   %8d µW\n", __func__,
                        i+1, j, marble->qsfps[i].rx_power[j]);
            }
        }
    }
}
