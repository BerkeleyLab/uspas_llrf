# LLRF Firmware for USPAS 2023

This repository holds the firmware for USPAS 2023 LLRF course, on the [Marble](https://github.com/BerkeleyLab/Marble) and [Zest](https://github.com/BerkeleyLab/Zest) platform.

# Global DSP frequency settings

Change [settings.mk](settings.mk) for the option of:

## LBNL ALSU settings:
|    **Signal**    |   **Ratio**  | **Value** |     |
|:----------------:|:------------:|:---------:|:---:|
|        MO        |              | 500       | MHz |
|        IF        |    MO / 12   | 41.67     | MHz |
|        LO        | MO / 12 * 11 | 458.33    | MHz |
|      dsp_clk     |    LO / 4    | 114.58    | MHz |
| IF_adc / dsp_clk |    4 / 11    |           |     |

Details see [Digital LLRF for ALS-U](https://arxiv.org/abs/2210.05095).

## USPAS LLRF settings:
|    **Signal**    |   **Ratio**  | **Value** |     |
|:----------------:|:------------:|:---------:|:---:|
|        MO        |              | 480       | MHz |
|        IF        |    MO / 24   | 20        | MHz |
|        LO        | MO / 24 * 23 | 460       | MHz |
|      dsp_clk     |    LO / 4    | 115       | MHz |
| IF_adc / dsp_clk |    4 / 23    |           |     |


## SLAC LEMP LLRF settings:
|    **Signal**    |    **Ratio**   | **Value** |     |
|:----------------:|:--------------:|:---------:|:---:|
|        MO        |                | 2856      | MHz |
|        IF        |    MO / 112    | 25.5      | MHz |
|        LO        | MO / 122 * 111 | 2830.5    | MHz |
|      dsp_clk     |     MO / 24    | 119       | MHz |
| IF_adc / dsp_clk |     3 / 14     |           |     |
|      dac_clk     |     MO / 12    | 238       | MHz |
| IF_dac           | MO / 336 * 11  | 93.5      | MHz |
| IF_dac / dac_clk |     11 / 28    |           |     |


# LLRF DSP verification

## RX, open loop and close loop simulation

See [llrf_dsp](llrf_dsp/tests/README.md).

## Overall monitoring, waveform, interlock
```
cd llrf_dsp
make llrf_shell_check
```

# Synthesize bitstream

```
cd top/marble_zest
make
```

# Boot-load soft core program

See [soc/marble_zest](soc/marble_zest/synth/README.md).
