# LLRF Firmware for USPAS 2023

This repository holds the firmware for USPAS 2023 LLRF course, on the [Marble](https://github.com/BerkeleyLab/Marble) and [Zest](https://github.com/BerkeleyLab/Zest) platform.

## Global DSP frequency settings

Change [settings.mk](settings.mk) for the option of:

### LBNL ALSU settings

|    **Signal**    |   **Ratio**  | **Value** |     |
|:----------------:|:------------:|:---------:|:---:|
|        MO        |              | 500       | MHz |
|  IF_adc, IF_dac  |    MO / 12   | 41.67     | MHz |
|        LO        | MO / 12 * 11 | 458.33    | MHz |
|      dsp_clk     |    LO / 4    | 114.58    | MHz |
|      dac_clk     |    LO / 2    | 229.17    | MHz |
| IF_adc / dsp_clk |    4 / 11    |           |     |
| IF_dac / dac_clk |    2 / 11    |           |     |

The Zest reference clock is LO.
Details see [Digital LLRF for ALS-U](https://arxiv.org/abs/2210.05095).

### USPAS LLRF settings

|    **Signal**    |   **Ratio**  | **Value** |     |
|:----------------:|:------------:|:---------:|:---:|
|        MO        |              | 480       | MHz |
|  IF_adc, IF_dac  |    MO / 24   | 20        | MHz |
|        LO        | MO / 24 * 23 | 460       | MHz |
|      dsp_clk     |    LO / 4    | 115       | MHz |
|      dac_clk     |    LO / 2    | 230       | MHz |
| IF_adc / dsp_clk |    4 / 23    |           |     |
| IF_dac / dac_clk |    2 / 23    |           |     |

The Zest reference clock is LO.

### SLAC LEMP LLRF settings

|    **Signal**    |    **Ratio**   | **Value** |     |
|:----------------:|:--------------:|:---------:|:---:|
|        MO        |                | 2856      | MHz |
|      IF_adc      |    MO / 112    | 25.5      | MHz |
|        LO        | MO / 112 * 111 | 2830.5    | MHz |
|      dsp_clk     |     MO / 24    | 119       | MHz |
|      dac_clk     |     MO / 12    | 238       | MHz |
|      IF_dac      | MO / 336 * 11  | 93.5      | MHz |
| IF_adc / dsp_clk |     3 / 14     |           |     |
| IF_dac / dac_clk |     11 / 28    |           |     |

The Zest reference clock is MO.

### ANL AWA LLRF settings

|    **Signal**    |    **Ratio**   | **Value** |     |
|:----------------:|:--------------:|:---------:|:---:|
|        MO        |                | 1300      | MHz |
|      IF_adc      |    MO / 65     | 20.0      | MHz |
|        LO        | MO / 65 * 66   | 1320      | MHz |
|      dsp_clk     |     LO / 14    | 94.28     | MHz |
|      dac_clk     |     LO / 7     | 188.6     | MHz |
|      IF_dac      | LO / 264 * 29  | 145.0     | MHz |
| IF_adc / dsp_clk |     7 / 33     |           |     |
| IF_dac / dac_clk |    203 / 264   |           |     |

The Zest reference clock is LO.

## LLRF DSP and verification

See [doc/README.md](doc/README.md).

```bash
cd llrf_dsp
make
```

## Synthesize bitstream

```bash
cd top/marble_zest
make FSET={TARGET}
```
Where TARGET is ALSU, AWA, LEMP or USPAS
## Boot-load soft core program

See [soc/marble_zest](soc/marble_zest/synth/README.md).
