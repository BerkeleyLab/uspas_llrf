#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <irq.h>
#include <generated/csr.h>
#include <libbase/uart.h>
#include <libbase/console.h>
#include <libbase/i2c.h>
#include <libliteeth/udp.h>


// i2c device address (7bit)
#define I2C_ADR_PCA9548     0x70
#define I2C_ADR_FMC1        0x50   // M24C02, GA0=0, GA1=0
#define I2C_ADR_INA219_A    0x42  // I2C_CH_APPL: U57
#define I2C_ADR_INA219_B    0x41  // I2C_CH_APPL: U32
#define I2C_ADR_INA219_C    0x40  // I2C_CH_APPL: U17
#define I2C_ADR_PCA9555_A   0x22  // I2C_CH_APPL: U34
#define I2C_ADR_PCA9555_B   0x21  // I2C_CH_APPL: U39
#define I2C_ADR_ADN4600     0x48  // I2C_CH_CLK:  U2

// i2c multiplexer channels
#define I2C_CH_FMC1     (1<<0)
#define I2C_CH_FMC2     (1<<1)
#define I2C_CH_CLK      (1<<2)
#define I2C_CH_SDRAM    (1<<3)
#define I2C_CH_QSFP1    (1<<4)
#define I2C_CH_QSFP2    (1<<5)
#define I2C_CH_APPL     (1<<6)


static bool i2c_mux_set(uint8_t ch)
{
    return i2c_write(I2C_ADR_PCA9548, ch, 0, 0);
}

static void i2c_scan(void)
{
    printf(" %s: [ ", __func__);
    for (unsigned addr=0; addr<=127; addr++){
        if(i2c_poll(addr))
            printf("%#2x ", addr);
    }
    printf("]\n");
}

static bool i2c_init(void)
{
    bool ret = true;
    unsigned char wbuf[2];
    unsigned char *buf;
    unsigned char pca_addr[2] = {I2C_ADR_PCA9555_A, I2C_ADR_PCA9555_B};
    buf = malloc(32);

    i2c_reset();
    printf(" %s: === Switching to APP: ===\n", __func__);
    ret &= i2c_mux_set(I2C_CH_APPL);
    i2c_scan();

    printf(" %s: === Switching to SDRAM: ===\n", __func__);
    ret &= i2c_mux_set(I2C_CH_SDRAM);
    i2c_scan();

    printf(" %s: === Switching to CLK: ===\n", __func__);
    ret &= i2c_mux_set(I2C_CH_CLK);
    i2c_scan();

    wbuf[0] = (2 << 4) | (1 << 3);  // broadcast FPGA_REF_CLK0 at IN2
    wbuf[1] = 1;
    ret &= i2c_write(I2C_ADR_ADN4600, 0x40, wbuf, 2);

    ret &= i2c_read(I2C_ADR_ADN4600, 0x40, buf, 2, false);
    printf(" %s: ADN4600 XPT 0x40:    %#8x\n", __func__, buf[0]);
    printf(" %s: ADN4600 XPT 0x41:    %#8x\n", __func__, buf[1]);
    ret &= i2c_read(I2C_ADR_ADN4600, 0x50, buf, 8, false);
    printf(" %s: ADN4600 XPT 0x50:    %#8x\n", __func__, buf[0]);
    printf(" %s: ADN4600 XPT 0x51:    %#8x\n", __func__, buf[1]);
    printf(" %s: ADN4600 XPT 0x54:    %#8x\n", __func__, buf[4]);
    printf(" %s: ADN4600 XPT 0x55:    %#8x\n", __func__, buf[5]);

    printf(" %s: === Switching to FMC1: ===\n", __func__);
    ret &= i2c_mux_set(I2C_CH_FMC1);
    i2c_scan();

    free(buf);
    printf(" %s:                  %s\n", __func__, ret ? "PASS": "FAIL");
    return ret;
}


static char *readstr(void)
{
    char c[2];
    static char s[64];
    static int ptr = 0;

    if(readchar_nonblock()) {
        c[0] = readchar();
        c[1] = 0;
        switch(c[0]) {
            case 0x7f:
            case 0x08:
                if(ptr > 0) {
                    ptr--;
                    putsnonl("\x08 \x08");
                }
                break;
            case 0x07:
                break;
            case '\r':
            case '\n':
                s[ptr] = 0x00;
                putsnonl("\n");
                ptr = 0;
                return s;
            default:
                if(ptr >= (int)(sizeof(s) - 1))
                    break;
                putsnonl(c);
                s[ptr] = c[0];
                ptr++;
                break;
        }
    }

    return NULL;
}

static char *get_token(char **str)
{
    char *c, *d;

    c = (char *)strchr(*str, ' ');
    if(c == NULL) {
        d = *str;
        *str = *str+strlen(*str);
        return d;
    }
    *c = 0;
    d = *str;
    *str = c+1;
    return d;
}

static void prompt(void)
{
    printf(""__DATE__" "__TIME__" RUNTIME>");
}

static void help(void)
{
    puts("Available commands:");
    puts("help                            - this command");
    puts("reboot                          - reboot CPU");
    puts("freq                            - freq test");
    puts("i2c                             - i2c test");
}

static void reboot(void)
{
    ctrl_reset_write(1);
}

static void freq_test(void)
{
    uint32_t freq;

    freq = config_clock_frequency_read();
    printf(" %s: f_sys = %ld Hz\n", __func__, freq);
    // timer0_uptime_latch_write(1);
    // uptime = timer0_uptime_cycles_read();
    // printf(" %s: uptime = %lld seconds.\n", __func__, uptime / freq);
}

static void i2c_test(void)
{
    i2c_init();
}

static void eth_reset(void)
{
    // ethphy_crg_reset_write(1);
    printf(" %s: eth phy reset done.\n", __func__);
}

static void console_service(void)
{
    char *str;
    char *token;

    str = readstr();
    if(str == NULL) return;
    token = get_token(&str);
    if(strcmp(token, "help") == 0)
        help();
    else if(strcmp(token, "reboot") == 0)
        reboot();
    else if(strcmp(token, "freq") == 0)
        freq_test();
    else if(strcmp(token, "i2c") == 0)
        i2c_test();
    else if(strcmp(token, "eth") == 0)
        eth_reset();
    prompt();
}

int main(void)
{
#ifdef CONFIG_CPU_HAS_INTERRUPT
    irq_setmask(0);
    irq_setie(1);
#endif
    uart_init();
    puts("\n Marble v1.2 built "__DATE__" "__TIME__"\n");

    help();
    prompt();

    // see tzset(), or /etc/localtime
    setenv("TZ", "PST8PDT,M3.2.0,M11.1.0", 1);
    while(1) {
        console_service();
    }

    return 0;
}
