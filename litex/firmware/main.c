#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <irq.h>
#include <generated/csr.h>
#include <libbase/uart.h>
#include <libbase/console.h>
#include <libbase/i2c.h>
#include <libliteeth/udp.h>


#define I2C_ADR_PCA9548 0x70

// static bool i2c_mux_set(uint8_t ch)
// {
//     return i2c_write(I2C_ADR_PCA9548, ch, 0, 0);
// }

static void i2c_scan(void)
{
    printf(" %s: [ ", __func__);
    for (unsigned addr=0; addr<=127; addr++){
        if(i2c_poll(addr))
            printf("%#2x ", addr);
    }
    printf("]\n");
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
    i2c_scan();
}

static void eth_reset(void)
{
    ethphy_crg_reset_write(1);
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
