#include <stdint.h>
#include "llrf.h"
#include "llrf_regs_addr.h"
#include "timer.h"
#include "settings.h"
#include "system.h"
#include "localbus.h"
#include "print.h"
#ifdef NONSTD_PRINTF
    #include "printf.h"
#else
    #include <stdio.h>
#endif

void wait_cbuf_ready(void) {
#ifndef SIMULATION
    uint32_t count=0;
    while (!CHECK_BIT(read_lb_reg(LLRF_CIRCLE_READY), 0)) {
        if (++count > 60000 ) {
            printf("waveform ready wait expired.\n");
            break;
        }
    }
#endif
}

void write_llrf_regs(const lbreg32_t *regmap, size_t len) {
    while ( len-- > 0 ){
        write_lb_reg(regmap->addr, regmap->val);
        regmap++;
    }
}

bool check_llrf_regs(const lbreg32_t *regmap, size_t len) {
    bool pass = true;
    int32_t temp;

    while ( len-- > 0 ){
        temp = read_lb_reg(regmap->addr);
        pass &= regmap->val == temp;
#ifndef SIMULATION
        debug_printf("%s: ( %#8x, %#8x )\n", "LLRF Check", regmap->addr, temp);
#endif
        regmap++;
    }
    return pass;
}

uint32_t read_avg_reg(uint32_t addr) {
    uint32_t sum=0;
    for (int ix=0; ix<8; ix++) {
        sum += read_lb_reg(addr);
    }
    return sum / 8;
}

void align_mo_phase(void) {
    int16_t mo_phs_cnt=0;
    uint32_t phase_shift_cnt=0, mo_adc_chan=0;

    mo_adc_chan = read_lb_reg(PRL_ADC_CHAN);
    write_lb_reg(RX_DDS_PHASE_SHIFT, 0);
    DELAY_MS(1);
    mo_phs_cnt = read_lb_reg(MON_PHS_0 + mo_adc_chan) >> 1;
    // print_str("Get MON_PHS = ");
    // print_dec_fix(mo_phs_cnt * 360, 16, 3);
    // print_str(" deg.\n");

    // 19 bit from 16 bit
    phase_shift_cnt = mo_phs_cnt << 3;
    write_lb_reg(RX_DDS_PHASE_SHIFT, phase_shift_cnt);
    DELAY_MS(1);
    mo_phs_cnt = read_lb_reg(MON_PHS_0 + mo_adc_chan) >> 1;
    printf("  %s: MO_PHS = %d\n", __func__, mo_phs_cnt);
    // print_str("Get MON_PHS = ");
    // print_dec_fix(mo_phs_cnt * 360, 15, 3);
    // print_str(" deg.\n");
}

void set_llrf_dac_permit(bool permit) {
    write_lb_reg(DAC_PERMIT, permit);
}

void set_llrf_bist_pass(bool pass) {
    write_lb_reg(SYSTEM_BIST_PASS, pass);
}

void reset_interlock_permit(void) {
    write_lb_reg(INLK_RESET_INLK, 1);
    write_lb_reg(INLK_RESET_INLK, 0);
}

void dbg_read_slowbuf(void) {
    int16_t dval[2];
    write_lb_reg(CIRCLE_BUF_FLIP, 1);
    wait_cbuf_ready();
    for (size_t ix=0; ix<8; ix++) {
        dval[0] = read_lb_reg(DSP_SLOW_ADC_MIN_0 + ix);
        dval[1] = read_lb_reg(DSP_SLOW_ADC_MAX_0 + ix);
        printf("ADC %d, Min: %6d,     MAX: %6d\n",
                ix, dval[0], dval[1]);
    }
    for (size_t ix=0; ix<8; ix++) {
        dval[0] = read_lb_reg(MON_AMP_0 + ix);
        dval[1] = read_lb_reg(MON_PHS_0 + ix) >> 1;
        printf("ADC %d, AMP: %6d cnt, PHS: %6d deg.\n",
               ix, dval[0], dval[1] * 360 / 0xffff);
    }
}

bool init_llrf(init_llrf_data_t *init_data) {
    bool pass;
    write_llrf_regs(init_data->regmap, init_data->len);
    pass = check_llrf_regs(init_data->regmap, init_data->len);
    // discard first waveform
    write_lb_reg(CIRCLE_BUF_FLIP, 1);
    wait_cbuf_ready();
    DELAY_MS(50);
    // align dds phase to MO
    // this only happens once at boot time, without checking,
    // to allow the system to come up (in a partially-working state)
    //  without relying on a stable MO input
    align_mo_phase();
    return pass;
}
