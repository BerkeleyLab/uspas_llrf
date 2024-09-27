#include "settings.h"
#include "marble.h"

// ----------------------------- ADN4600 -----------------------------
// 500mV output swing to satisfy DS182 table 55
t_reg8 adn4600_regmap[] = {
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
    // IP0-3: EXT0_CLK,     EX1_CLK,        FPGA_REF_CLK0,  SI570_CLK,
    // IP4-7: FMC1_GBTCLK0, FMC1_GBTCLK1,   FMC2_GBTCLK0,   FMC2_GBTCLK1
    // OP0-3: MGT_CLK_0,    MGT_CLK_1,      OUT1_CLK,       NC,
    // OP4-7: MGT_CLK_2,    MGT_CLK_3,      NC,             NC
    // Configure XPT (first bank of latches)
    {0x40, (2 << 4) | 0},   // FPGA_REF_CLK0    -> MGT_CLK_0 at OUT0
    {0x40, (3 << 4) | 1},   // SI570_CLK        -> MGT_CLK_1 at OUT1
    {0x40, (4 << 4) | 4},   // FMC1_GBTCLK0     -> MGT_CLK_2 at OUT4
    {0x40, (6 << 4) | 5},   // FMC2_GBTCLK0     -> MGT_CLK_3 at OUT5
    // Update XPT (second bank of latches, output connections programmed simultaneously)
    {0x41, 1},
};

// ----------------------------- INA219 -----------------------------
// VBUS_MAX = 12V
// VSHUNT_MAX = 0.08    (PGA = /8, +-320mV @ config=0x399f)
// RSHUNT = 0.082
// CurrentLSB = 1e-5 A (10uA per bit)
//   Cal = trunc (0.04096 / (CurrentLSB * RSHUNT)) = 49950 (0xc31e)
t_reg16 ina219_fmc_regmap[] = {
    {0, 0x399f},
    {5, 0xc31e}
};

// RSHUNT = 0.082 / 3 for I2C_ADR_INA219_12V
// CurrentLSB = 1e-4 A (100uA per bit)
// hex(int(0.04096 / (0.082 / 3 * 1e-4))) = 0x3a88
t_reg16 ina219_12v_regmap[] = {
    {0, 0x399f},
    {5, 0x3a88}
};

// ----------------------------- PCA9555 -----------------------------
// U34
// P0[7:3] = [QSFP1_MOD_SELB, QSFP1_RSTB, QSFP1_MOD_PRS, QSFP1_LPMODE]
// P1[7:3] = [QSFP2_MOD_SELB, QSFP2_RSTB, QSFP2_MOD_PRS, QSFP2_LPMODE]
t_reg8 pca9555_u34_regmap[] = {
    {2, 0x48},  // Output: assert LPMODE, RSTB, deassert MOD_SELB on QSFP1
    {3, 0x48},  // Output: assert LPMODE, RSTB, deassert MOD_SELB on QSFP2
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
    {2, 0x00},  // Output: Write protection, Enable SI570 (NCB & NBB both are low polarity)
    {3, 0x80},  // Output: LED on, do not reset ADN4600
    {4, 0},
    {5, 0},
    {6, 0xfe},  // Config: low for enabling output (only for Si570)
    {7, 0x73}   // Config: low for enabling output: CLK_MUX, LD13, LD14
};

const marble_init_t marble_init_data = {
    .marble_variant = MARBLE_VAR_UNKNOWN,
    .adn4600_data = {
        .len = ARRAY_SIZE(adn4600_regmap),
        .regmap = adn4600_regmap
    },
    .ina219_fmc1_data = {
        .len = ARRAY_SIZE(ina219_fmc_regmap),
        .regmap = ina219_fmc_regmap
    },
    .ina219_fmc2_data = {
        .len = ARRAY_SIZE(ina219_fmc_regmap),
        .regmap = ina219_fmc_regmap
    },
    .ina219_12v_data = {
        .len = ARRAY_SIZE(ina219_12v_regmap),
        .regmap = ina219_12v_regmap
    },
    .pca9555_qsfp_data = {
        .len = ARRAY_SIZE(pca9555_u34_regmap),
        .regmap = pca9555_u34_regmap
    },
    .pca9555_misc_data = {
        .len = ARRAY_SIZE(pca9555_u39_regmap),
        .regmap = pca9555_u39_regmap
    },
    .si570_freq_hz = 125000000,
    .enable_evr_gtx = false
};
