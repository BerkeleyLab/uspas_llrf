# LLRF Firmware for USPAS 2022

This repository holds the firmware for USPAS 2022 LLRF course, on the [Marble](https://github.com/BerkeleyLab/Marble) and [Zest](https://github.com/BerkeleyLab/Zest) platform.

# Global DSP frequency settings

Change [settings.mk](settings.mk) for the option of:

## LBNL ALSU settings:
- IF = MO / 12          = 41.67 MHz
- LO = MO / 12 * 11     = 458.33 MHz
- dsp_clk               = LO / 4 = 114.58 MHz
- IF / CLK              = 4 / 11
Details see [Digital LLRF for ALS-U](https://arxiv.org/abs/2210.05095)

## Brazilian Light Source LLRF settings:
- IF = MO / 24          = 20.83 MHz
- LO = MO / 24 * 23     = 479.17 MHz
- dsp_clk               = LO / 4 = 119.79 MHz
- IF / CLK              = 4 / 23
Details see [SIRIUS digital LLRF](https://accelconf.web.cern.ch/ipac2019/papers/thpts060.pdf).

# LLRF DSP

see [llrf_dsp](llrf_dsp/) with numerical simulations of:
## Non-IQ digital down conversion
    ```
    make noniq_ddc_check
    ```
## Feedback control
    ```
    make dsp_core_check
    ```

## Overall monitoring, waveform, interlock
    ```
    make llrf_shell_check
    ```
 