#include <stdint.h>
#include "llrf.h"
#include "llrf_regs_addr.h"
#include "timer.h"
#include "settings.h"
#include "system.h"
#include "localbus.h"
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

bool align_mo_phase(void) {
    bool pass = true;
    return pass;
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
    int16_t dval;
    write_lb_reg(CIRCLE_BUF_FLIP, 1);
    wait_cbuf_ready();
    for (size_t ix=0; ix<8; ix++) {
        dval = read_lb_reg(DSP_SLOW_ADC_MIN_0 + ix);
        printf("ADC %d, MIN %d\n", ix, dval);
        dval = read_lb_reg(DSP_SLOW_ADC_MAX_0 + ix);
        printf("ADC %d, MAX %d\n", ix, dval);
        dval = read_lb_reg(MON_AMP_0 + ix);
        printf("ADC %d, AMP %d\n", ix, dval);
    }
}

bool init_llrf(init_llrf_data_t *init_data) {
    bool pass;
    write_llrf_regs(init_data->regmap, init_data->len);
    pass = check_llrf_regs(init_data->regmap, init_data->len);
    // discard first waveform
    write_lb_reg(CIRCLE_BUF_FLIP, 1);
    wait_cbuf_ready();
    return pass;
}
