# Synthesizing and building firmware
```bash
    make
```
Note that this Synthesizing uses `system_top.v` which is for testing the soft core, and does not contain LLRF DSP.
The full LLRF Synthesizing should be done at `top/marble_zest` directory instead.

To build CPU program only, use:
```bash
    make system32.dat
```

# Programming to hardware

```bash
    make system_config
```

# Reloading firmware
Check Marble UART device, default is `/dev/ttyUSB3` in `Makefile`.
This port is usually next to the last UART port of the Marble MMC.

For boot loading the CPU program after revising the source code,

```bash
    make system_load BOOTLOADER_SERIAL=/dev/ttyUSB2
```

# Booting log examples
## Normal booting log (#define DEBUG_PRINT 0)

```
  _   _ ____  ____   _    ____    _     _     ____  _____ 
 | | | / ___||  _ \ / \  / ___|  | |   | |   |  _ \|  ___|
 | | | \___ \| |_) / _ \ \___ \  | |   | |   | |_) | |_   
 | |_| |___) |  __/ ___ \ ___) | | |___| |___|  _ <|  _|  
  \___/|____/|_| /_/   \_\____/  |_____|_____|_| \_\_|

==== Marble Init       ====  : PASS.
  Fclk  DSP_CLK:  114.583 MHz
==== ZEST DSP CLK Freq====  : PASS.
==== ZEST ADC(AD9653) ====  : PASS.
==== ZEST DAC(AD9781) ====  : PASS.
==== ZEST AD7794      ====  : PASS.
==== ZEST AMC7823     ====  : PASS.
  Fclk ADC0_DIV:  114.582 MHz
  Clk DIV freq  0 Check: PASS.
    Phase ADC0_DIV clk: 0x9a  1.203 UI
    Phase ADC0_DIV clk: 0x1a  0.203 UI
    Phase ADC0_DIV clk: 0x9a  1.203 UI
    Phase ADC0_DIV clk: 0x18  0.187 UI
    Phase ADC0_DIV clk: 0x9a  1.203 UI
    Phase ADC0_DIV clk: 0x19  0.195 UI
    Phase ADC0_DIV clk: 0x9b  1.210 UI
    Phase ADC0_DIV clk: 0x59  0.695 UI
  Phase ADC0_DIV clk aligned. retry = 7.
  Clk DIV phase 0 Check: PASS.
  Fclk ADC1_DIV:  114.583 MHz
  Clk DIV freq  1 Check: PASS.
    Phase ADC1_DIV clk: 0x82  1.015 UI
    Phase ADC1_DIV clk: 0x41  0.507 UI
  Phase ADC1_DIV clk aligned. retry = 1.
  Clk DIV phase 1 Check: PASS.
  Fclk  DAC_DCO:  114.583 MHz
  DAC DCO freq  2 Check: PASS.
    Phase  DAC_DCO clk: 0x33  0.398 UI
  DAC DCO phase 2 Check: PASS.
  ADC 0
    idelay =  0xc, bitslipts = 2
    idelay =  0xb, bitslipts = 2
  ADC 1
    idelay =  0xc, bitslipts = 2
    idelay =  0xe, bitslipts = 2
  ADC 2
    idelay =  0xe, bitslipts = 2
    idelay =  0xd, bitslipts = 2
  ADC 3
    idelay =  0xb, bitslipts = 2
    idelay =  0xb, bitslipts = 2
  ADC 4
    idelay =  0xa, bitslipts = 2
    idelay =  0x9, bitslipts = 2
  ADC 5
    idelay =  0xb, bitslipts = 2
    idelay =  0xc, bitslipts = 2
  ADC 6
    idelay = 0x16, bitslipts = 2
    idelay = 0x13, bitslipts = 2
  ADC 7
    idelay = 0x15, bitslipts = 2
    idelay = 0x15, bitslipts = 2
==== ZEST ADC LVDS    ====  : PASS.
  ADC 0: delay 1667 ns
  ADC 1: delay 1667 ns
  ADC 2: delay 1666 ns
  ADC 3: delay 1667 ns
  ADC 4: delay 1667 ns
  ADC 5: delay 1667 ns
  ADC 6: delay 1666 ns
  ADC 7: delay 1667 ns
==== ZEST ADC PN9 Check====  : PASS.
AD9781 Alignment:
 Found SMP value: 12.
==== ZEST DAC SMP Check====  : PASS.
==== ZEST Init         ====  : PASS.
```

## Verbose booting log (#define DEBUG_PRINT 1)

```
  _   _ ____  ____   _    ____    _     _     ____  _____ 
 | | | / ___||  _ \ / \  / ___|  | |   | |   |  _ \|  ___|
 | | | \___ \| |_) / _ \ \___ \  | |   | |   | |_) | |_   
 | |_| |___) |  __/ ___ \ ___) | | |___| |___|  _ <|  _|  
  \___/|____/|_| /_/   \_\____/  |_____|_____|_| \_\_|
==== Marble Init       ====  : PASS.
  Fclk  DSP_CLK:  114.583 MHz
==== ZEST DSP CLK Freq====  : PASS.
SPI_Chceck: (0000, 0x000018)
SPI_Chceck: (0x08, 00000000)
SPI_Chceck: (0x09, 0x000001)
SPI_Chceck: (0x00, 0x000046)
SPI_Chceck: (0x14, 0x000007)
SPI_Chceck: (0x18, 0x000004)
SPI_Chceck: (0x21, 0x000030)
SPI_Chceck: (0000, 0x000018)
SPI_Chceck: (0x08, 00000000)
SPI_Chceck: (0x09, 0x000001)
SPI_Chceck: (0x00, 0x000046)
SPI_Chceck: (0x14, 0x000007)
SPI_Chceck: (0x18, 0x000004)
SPI_Chceck: (0x21, 0x000030)
==== ZEST ADC(AD9653) ====  : PASS.
Dump ADC0 registers:
  ADC Reg Dump: (0000, 0x000018)
  ADC Reg Dump: (0x01, 0x0000b5)
  ADC Reg Dump: (0x02, 0x000061)
  ADC Reg Dump: (0x05, 0x00003f)
  ADC Reg Dump: (0x08, 00000000)
  ADC Reg Dump: (0x09, 0x000001)
  ADC Reg Dump: (0x0b, 00000000)
  ADC Reg Dump: (0x0c, 00000000)
  ADC Reg Dump: (0x0d, 00000000)
  ADC Reg Dump: (0x10, 00000000)
  ADC Reg Dump: (0x14, 0x000007)
  ADC Reg Dump: (0x15, 00000000)
  ADC Reg Dump: (0x16, 0x000003)
  ADC Reg Dump: (0x18, 0x000004)
  ADC Reg Dump: (0x19, 00000000)
  ADC Reg Dump: (0x1a, 00000000)
  ADC Reg Dump: (0x1b, 00000000)
  ADC Reg Dump: (0x1c, 00000000)
  ADC Reg Dump: (0x21, 0x000030)
  ADC Reg Dump: (0x22, 00000000)
  ADC Reg Dump: (0x00, 0x000046)
  ADC Reg Dump: (0x01, 00000000)
  ADC Reg Dump: (0x02, 00000000)
  ADC Reg Dump: (0x09, 00000000)
Dump ADC1 registers:
  ADC Reg Dump: (0000, 0x000018)
  ADC Reg Dump: (0x01, 0x0000b5)
  ADC Reg Dump: (0x02, 0x000061)
  ADC Reg Dump: (0x05, 0x00003f)
  ADC Reg Dump: (0x08, 00000000)
  ADC Reg Dump: (0x09, 0x000001)
  ADC Reg Dump: (0x0b, 00000000)
  ADC Reg Dump: (0x0c, 00000000)
  ADC Reg Dump: (0x0d, 00000000)
  ADC Reg Dump: (0x10, 00000000)
  ADC Reg Dump: (0x14, 0x000007)
  ADC Reg Dump: (0x15, 00000000)
  ADC Reg Dump: (0x16, 0x000003)
  ADC Reg Dump: (0x18, 0x000004)
  ADC Reg Dump: (0x19, 00000000)
  ADC Reg Dump: (0x1a, 00000000)
  ADC Reg Dump: (0x1b, 00000000)
  ADC Reg Dump: (0x1c, 00000000)
  ADC Reg Dump: (0x21, 0x000030)
  ADC Reg Dump: (0x22, 00000000)
  ADC Reg Dump: (0x00, 0x000046)
  ADC Reg Dump: (0x01, 00000000)
  ADC Reg Dump: (0x02, 00000000)
  ADC Reg Dump: (0x09, 00000000)
SPI_Chceck: (0000, 00000000)
SPI_Chceck: (0x02, 00000000)
SPI_Chceck: (0x03, 00000000)
SPI_Chceck: (0x04, 00000000)
SPI_Chceck: (0x05, 0x00000c)
SPI_Chceck: (0x0a, 0x00000f)
==== ZEST DAC(AD9781) ====  : PASS.
Dump DAC registers:
  DAC Reg Dump: (0000, 00000000)
  DAC Reg Dump: (0x02, 00000000)
  DAC Reg Dump: (0x03, 00000000)
  DAC Reg Dump: (0x04, 00000000)
  DAC Reg Dump: (0x05, 0x00000c)
  DAC Reg Dump: (0x06, 0x000008)
  DAC Reg Dump: (0x0a, 0x00000f)
  DAC Reg Dump: (0x0b, 0x0000f9)
  DAC Reg Dump: (0x0c, 0x000001)
  DAC Reg Dump: (0x0d, 00000000)
  DAC Reg Dump: (0x0e, 00000000)
  DAC Reg Dump: (0x0f, 0x0000f9)
  DAC Reg Dump: (0x10, 0x000001)
  DAC Reg Dump: (0x11, 00000000)
  DAC Reg Dump: (0x12, 00000000)
  DAC Reg Dump: (0x1a, 00000000)
  DAC Reg Dump: (0x1b, 00000000)
  DAC Reg Dump: (0x1c, 00000000)
  DAC Reg Dump: (0x1d, 00000000)
  DAC Reg Dump: (0x1e, 00000000)
  DAC Reg Dump: (0x1f, 0x000001)
    wait_ad7794_spi_ready: 233710
SPI_Chceck: (0x01, 0x00200a)
SPI_Chceck: (0x02, 0x000090)
==== ZEST AD7794      ====  : PASS.
SPI_Chceck: (0x4b, 0x008080)
SPI_Chceck: (0x4d, 0x008010)
==== ZEST AMC7823     ====  : PASS.
  Fclk ADC0_DIV:  114.583 MHz
  Clk DIV freq  0 Check: PASS.
    Phase ADC0_DIV clk: 0x9a  1.203 UI
    Phase ADC0_DIV clk: 0x1a  0.203 UI
    Phase ADC0_DIV clk: 0x9a  1.203 UI
    Phase ADC0_DIV clk: 0x1a  0.203 UI
    Phase ADC0_DIV clk: 0x9a  1.203 UI
    Phase ADC0_DIV clk: 0x18  0.187 UI
    Phase ADC0_DIV clk: 0x9a  1.203 UI
    Phase ADC0_DIV clk: 0x1a  0.203 UI
    Phase ADC0_DIV clk: 0x9a  1.203 UI
    Phase ADC0_DIV clk: 0x1a  0.203 UI
    Phase ADC0_DIV clk: 0xd8  1.687 UI
    Phase ADC0_DIV clk: 0x5a  0.703 UI
  Phase ADC0_DIV clk aligned. retry = 11.
  Clk DIV phase 0 Check: PASS.
  Fclk ADC1_DIV:  114.582 MHz
  Clk DIV freq  1 Check: PASS.
    Phase ADC1_DIV clk: 0x83  1.023 UI
    Phase ADC1_DIV clk: 0xc2  1.515 UI
    Phase ADC1_DIV clk: 0x82  1.015 UI
    Phase ADC1_DIV clk:  0x3  0.023 UI
    Phase ADC1_DIV clk: 0x81  1.007 UI
    Phase ADC1_DIV clk:  0x4  0.031 UI
    Phase ADC1_DIV clk: 0x83  1.023 UI
    Phase ADC1_DIV clk:  0x4  0.031 UI
    Phase ADC1_DIV clk: 0x83  1.023 UI
    Phase ADC1_DIV clk:  0x1  0.007 UI
    Phase ADC1_DIV clk: 0x83  1.023 UI
    Phase ADC1_DIV clk:  0x2  0.015 UI
    Phase ADC1_DIV clk: 0x82  1.015 UI
    Phase ADC1_DIV clk:  0x2  0.015 UI
    Phase ADC1_DIV clk: 0x84  1.031 UI
    Phase ADC1_DIV clk:  0x3  0.023 UI
    Phase ADC1_DIV clk: 0x83  1.023 UI
    Phase ADC1_DIV clk: 0x42  0.515 UI
  Phase ADC1_DIV clk aligned. retry = 17.
  Clk DIV phase 1 Check: PASS.
  Fclk  DAC_DCO:  114.583 MHz
  DAC DCO freq  2 Check: PASS.
    Phase  DAC_DCO clk: 0x33  0.398 UI
  DAC DCO phase 2 Check: PASS.
  ADC 0
    idelay =  0xc, bitslipts = 2
    idelay =  0xb, bitslipts = 2
  ADC 1
    idelay =  0xc, bitslipts = 2
    idelay =  0xd, bitslipts = 2
  ADC 2
    idelay =  0xe, bitslipts = 2
    idelay =  0xd, bitslipts = 2
  ADC 3
    idelay =  0xb, bitslipts = 2
    idelay =  0xb, bitslipts = 2
  ADC 4
    idelay =  0xa, bitslipts = 2
    idelay =  0x9, bitslipts = 2
  ADC 5
    idelay =  0xb, bitslipts = 2
    idelay =  0xc, bitslipts = 2
  ADC 6
    idelay = 0x16, bitslipts = 2
    idelay = 0x13, bitslipts = 2
  ADC 7
    idelay = 0x16, bitslipts = 2
    idelay = 0x15, bitslipts = 2
==== ZEST ADC LVDS    ====  : PASS.
PN9: 0xb668
PN9: 0x7787
PN9: 0xfc1e
PN9: 0xf8b9
PN9: 0x904a
PN9: 0x768f
PN9: 0x3e6c
PN9: 0x548e
PN9: 0x36ae
PN9: 0x2622
PN9: 0x0108
PN9: 0xc272
PN9: 0xac37
PN9: 0xa6e4
PN9: 0x50ad
PN9: 0x3f64
PN9: 0x96fc
PN9: 0x9a99
PN9: 0x80c6
PN9: 0x51a5
PN9: 0xfd16
PN9: 0x3acb
PN9: 0x3c7d
PN9: 0xd06b
PN9: 0x6ec1
PN9: 0x6bea
PN9: 0xa052
PN9: 0xbcbb
PN9: 0x81ce
PN9: 0x93d7
PN9: 0x5121
PN9: 0x9c2f
ADC chan 0 waveform:
  ix  0, dout: 0xa6e4
  ix  1, dout: 0x50ad
  ix  2, dout: 0x3f64
  ix  3, dout: 0x96fc
  ix  4, dout: 0x9a99
  ix  5, dout: 0x80c6
  ix  6, dout: 0x51a5
  ix  7, dout: 0xfd16
  ADC 0: delay 1668 ns
ADC chan 1 waveform:
  ix  0, dout: 0xa6e4
  ix  1, dout: 0x50ad
  ix  2, dout: 0x3f64
  ix  3, dout: 0x96fc
  ix  4, dout: 0x9a99
  ix  5, dout: 0x80c6
  ix  6, dout: 0x51a5
  ix  7, dout: 0xfd16
  ADC 1: delay 1668 ns
ADC chan 2 waveform:
  ix  0, dout: 0xac37
  ix  1, dout: 0xa6e4
  ix  2, dout: 0x50ad
  ix  3, dout: 0x3f64
  ix  4, dout: 0x96fc
  ix  5, dout: 0x9a99
  ix  6, dout: 0x80c6
  ix  7, dout: 0x51a5
  ADC 2: delay 1667 ns
ADC chan 3 waveform:
  ix  0, dout: 0xa6e4
  ix  1, dout: 0x50ad
  ix  2, dout: 0x3f64
  ix  3, dout: 0x96fc
  ix  4, dout: 0x9a99
  ix  5, dout: 0x80c6
  ix  6, dout: 0x51a5
  ix  7, dout: 0xfd16
  ADC 3: delay 1668 ns
ADC chan 4 waveform:
  ix  0, dout: 0xa6e4
  ix  1, dout: 0x50ad
  ix  2, dout: 0x3f64
  ix  3, dout: 0x96fc
  ix  4, dout: 0x9a99
  ix  5, dout: 0x80c6
  ix  6, dout: 0x51a5
  ix  7, dout: 0xfd16
  ADC 4: delay 1668 ns
ADC chan 5 waveform:
  ix  0, dout: 0xa6e4
  ix  1, dout: 0x50ad
  ix  2, dout: 0x3f64
  ix  3, dout: 0x96fc
  ix  4, dout: 0x9a99
  ix  5, dout: 0x80c6
  ix  6, dout: 0x51a5
  ix  7, dout: 0xfd16
  ADC 5: delay 1668 ns
ADC chan 6 waveform:
  ix  0, dout: 0xa6e4
  ix  1, dout: 0x50ad
  ix  2, dout: 0x3f64
  ix  3, dout: 0x96fc
  ix  4, dout: 0x9a99
  ix  5, dout: 0x80c6
  ix  6, dout: 0x51a5
  ix  7, dout: 0xfd16
  ADC 6: delay 1668 ns
ADC chan 7 waveform:
  ix  0, dout: 0xac37
  ix  1, dout: 0xa6e4
  ix  2, dout: 0x50ad
  ix  3, dout: 0x3f64
  ix  4, dout: 0x96fc
  ix  5, dout: 0x9a99
  ix  6, dout: 0x80c6
  ix  7, dout: 0x51a5
  ADC 7: delay 1667 ns
==== ZEST ADC PN9 Check====  : PASS.
AD9781 Alignment:
 SMP  0 HLD: 1111111111100000 11
        SET: 1111111111111111 15
 SMP  1 HLD: 1111111110000000  9
        SET: 1111111111111111 15
 SMP  2 HLD: 1111111000000000  7
        SET: 1111111111111111 15
 SMP  3 HLD: 1111100000000000  5
        SET: 1111111111111111 15
 SMP  4 HLD: 1110000000000000  3
        SET: 1111111111111111 15
 SMP  5 HLD: 1000000000000000  1
        SET: 1111111111111111 15
 SMP  6 HLD: 0000000000000000 15
        SET: 0011111111111111  2
 SMP  7 HLD: 0000000000000000 15
        SET: 0000111111111111  4
 SMP  8 HLD: 0000000000000000 15
        SET: 0000001111111111  6
 SMP  9 HLD: 0000000000000000 15
        SET: 0000000011111111  8
 SMP 10 HLD: 0000000000000000 15
        SET: 0000000000111111 10
 SMP 11 HLD: 0000000000000000 15
        SET: 0000000000001111 12
 SMP 12 HLD: 0000000000000000 15
        SET: 0000000000000011 14
 SMP 13 HLD: 0000000000000000 15
        SET: 0000000000000000 15
 SMP 14 HLD: 0000000000000000 15
        SET: 0000000000000000 15
 SMP 15 HLD: 0000000000000000 15
        SET: 0000000000000000 15
 SMP 16 HLD: 0000000000000000 15
        SET: 0000000000000000 15
 SMP 17 HLD: 0000000000000000 15
        SET: 0000000000000000 15
 SMP 18 HLD: 0000000000000000 15
        SET: 0000000000000000 15
 SMP 19 HLD: 0000000000000000 15
        SET: 0000000000000000 15
 SMP 20 HLD: 0000000000000000 15
        SET: 0000000000000000 15
 SMP 21 HLD: 0000000000000000 15
        SET: 0000000000000000 15
 SMP 22 HLD: 0000000000000000 15
        SET: 0000000000000000 15
 SMP 23 HLD: 0000000000000000 15
        SET: 0000000000000000 15
 SMP 24 HLD: 0000000000000000 15
        SET: 0000000000000000 15
 SMP 25 HLD: 0000000000000011 14
        SET: 0000000000000000 15
 SMP 26 HLD: 0000000000001111 12
        SET: 0000000000000000 15
 SMP 27 HLD: 0000000000011111 11
        SET: 0000000000000000 15
 SMP 28 HLD: 0000000001111111  9
        SET: 0000000000000000 15
 SMP 29 HLD: 0000000001111111  9
        SET: 0000000000000000 15
 SMP 30 HLD: 0000000001111111  9
        SET: 0000000000000000 15
 SMP 31 HLD: 0000000001111111  9
        SET: 0000000000000000 15
 Found SMP value: 12.
==== ZEST DAC SMP Check====  : PASS.
==== ZEST Init         ====  : PASS.

## Diagnostics
---- Test Data: ----
  Fclk  DSP_CLK:  114.583 MHz
Freq 0 Check: PASS
  Fclk ADC0_DIV:  114.583 MHz
Freq 1 Check: PASS
  Fclk ADC1_DIV:  114.583 MHz
Freq 2 Check: PASS
ZEST AMC7823 ADC:
  ADC 0 Val: 0x022d Volt:  0.339[V]
  ADC 1 Val: 0x1115 Volt:  0.168[V]
  ADC 2 Val: 0x208f Volt:  0.087[V]
  ADC 3 Val: 0x304d Volt:  0.046[V]
  ADC 4 Val: 0x4ae6 Volt:  1.702[V]
  ADC 5 Val: 0x5750 Volt:  1.142[V]
  ADC 6 Val: 0x62b8 Volt:  0.424[V]
  ADC 7 Val: 0x7a8b Volt:  1.647[V]
  ADC 8 Val: 0x80c2 Temp:  30.125[C]
ZEST AD7794 ADC:
    wait_ad7794_spi_ready: 0
  AIN 1: 0xca9b61 Volt:  0.925[V]
    wait_ad7794_spi_ready: 232811
  AIN 2: 0xda70ef Volt:  0.998[V]
    wait_ad7794_spi_ready: 233776
  AIN 3: 0xf48f4a Volt:  1.117[V]
    wait_ad7794_spi_ready: 233779
  AIN 4: 0x7af3a6 Volt:  0.561[V]
    wait_ad7794_spi_ready: 233783
  AIN 5: 0x8304e3 Volt:  0.598[V]
    wait_ad7794_spi_ready: 233786
  AIN 6: 0xfe3ebd Volt:  1.161[V]
  Fclk  DSP_CLK:  114.583 MHz
Freq 0 Check: PASS
  Fclk ADC0_DIV:  114.583 MHz
Freq 1 Check: PASS
  Fclk ADC1_DIV:  114.583 MHz
Freq 2 Check: PASS
  Fclk  DAC_DCO:  114.583 MHz
Freq 3 Check: PASS
    Phase ADC0_DIV clk: 0x59  0.695 UI
  Phase ADC0_DIV clk aligned. retry = 0.
    Phase ADC1_DIV clk: 0x43  0.523 UI
  Phase ADC1_DIV clk aligned. retry = 0.
    Phase  DAC_DCO clk: 0x33  0.398 UI
ADC chan 0 dout: -120
ADC chan 1 dout: -172
ADC chan 2 dout: -168
ADC chan 3 dout: -147
ADC chan 4 dout: -278
ADC chan 5 dout: -239
ADC chan 6 dout:  -95
ADC chan 7 dout: -126

INA219 FMC1:
Vbus:     11904 mV
current:      0 mA
PCA9555 1:
P0:      0b11111101
P1:      0b11111111
INA219 FMC2:
Vbus:     11904 mV
current:     81 mA
PCA9555 2:
P0:      0b11111111
P1:      0b11110011
XADC    Temp   :  56.47 degC
XADC    VCCINT :  1.00  V
XADC    VCCAUX :  1.79  V
XADC    VCCBRAM:  1.00  V
```

