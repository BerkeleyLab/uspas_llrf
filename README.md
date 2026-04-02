# LLRF Firmware for USPAS 2023

This repository holds the firmware for USPAS 2023 LLRF course, on the [Marble](https://github.com/BerkeleyLab/Marble) and [Zest](https://github.com/BerkeleyLab/Zest) platform.

## Global DSP frequency settings

Change [settings.mk](settings.mk) for the option of:

### LBNL ALSU settings

|    **Signal**    |   **Ratio**  | **Value** |     |
|:----------------:|:------------:|:---------:|:---:|
|        MO        |              | 500.394   | MHz |
|  IF_adc, IF_dac  |    MO / 12   |  41.699   | MHz |
|        LO        | MO / 12 * 11 | 458.695   | MHz |
|      dsp_clk     |    LO / 4    | 114.674   | MHz |
|      dac_clk     |    LO / 2    | 229.347   | MHz |
| IF_adc / dsp_clk |    4 / 11    |           |     |
| IF_dac / dac_clk |    2 / 11    |           |     |
|   GT ref_clk     |    MO / 4    | 125.099   | MHz |

The Zest reference clock is LO.
Details see [1](https://arxiv.org/abs/2210.05095).

### USPAS LLRF settings

|    **Signal**    |   **Ratio**  | **Value** |     |
|:----------------:|:------------:|:---------:|:---:|
|        MO        |              | 480       | MHz |
|  IF_adc, IF_dac  |    MO / 24   |  20       | MHz |
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
|      IF_adc      |    MO / 112    |   25.5    | MHz |
|        LO        | MO / 112 * 111 | 2830.5    | MHz |
|      dsp_clk     |     MO / 24    |  119      | MHz |
|      dac_clk     |     MO / 12    |  238      | MHz |
|      IF_dac      | MO / 336 * 11  |   93.5    | MHz |
| IF_adc / dsp_clk |     3 / 14     |           |     |
| IF_dac / dac_clk |     11 / 28    |           |     |
|   GT ref_clk     |    MO / 4      | 119.0     | MHz |

The Zest reference clock is MO.

### ANL AWA LLRF settings

|    **Signal**    |    **Ratio**   | **Value** |     |
|:----------------:|:--------------:|:---------:|:---:|
|        MO        |                | 1300      | MHz |
|      IF_adc      |    MO / 65     |   20.0    | MHz |
|        LO        | MO / 65 * 66   | 1320      | MHz |
|      dsp_clk     |     LO / 14    |   94.28   | MHz |
|      dac_clk     |     LO / 7     |  188.6    | MHz |
|      IF_dac      | LO / 264 * 29  |  145.0    | MHz |
| IF_adc / dsp_clk |     7 / 33     |           |     |
| IF_dac / dac_clk |    203 / 264   |           |     |

The Zest reference clock is LO.

DAC is in mix-mode for second Nyquist zone sampling.

### FNAL VTS LLRF settings

|    **Signal**    |    **Ratio**   | **Value** |     |
|:----------------:|:--------------:|:---------:|:---:|
|        MO        |                | 1295.275  | MHz |
|      IF_adc      |    MO / 65     |   19.927  | MHz |
|        LO        | MO / 65 * 66   | 1315.202  | MHz |
|      dsp_clk     |     LO / 14    |   93.943  | MHz |
|      dac_clk     |     LO / 7     |  188.6    | MHz |
|      IF_dac      |     MO / 65    |   19.927  | MHz |
| IF_adc / dsp_clk |     7 / 33     |           |     |
| IF_dac / dsp_clk |     7 / 33     |           |     |

The Zest reference clock is LO.

## 🚀 Quick Start

### LLRF DSP and verification

See [doc/README.md](doc/README.md).

```bash
pip install -e .
cd llrf_dsp
make
```

### Synthesize bitstream

```bash
cd top/marble_zest
make FSET={TARGET}
```
Where TARGET is ALSU, AWA, LEMP or USPAS.

### Boot-load soft core program

See [soc/marble_zest](soc/marble_zest/synth/README.md).

### Chassis I/O

The connections of misc. signals to Marble / Zest IO ports are summarized in the following table.

|                       |     **USPAS**    |     **ALSU**     |            **LEMP**           |        **AWA**        |
|----------------------:|:----------------:|:----------------:|:-----------------------------:|:---------------------:|
| Marble MMC PMOD (J16) | Front Panel OLED | Front Panel OLED | Front Panel OLED              |                       |
|    Marble PMOD1 (J12) | Trigger Input    | ARC Detectors    | Trigger Output, Interlock I/O |                       |
|    Marble PMOD2 (J13) |                  | Interlock I/O    |                               | Front Panel LED       |
|     Marble QSFP2 Ch.1 |                  | Timing EVR       | Timing EVR                    |                       |
|      Zest PMOD1 (J17) |                  | Modbus RTU       |                               | Up Conv. Enable [7:6] |
|      Zest PMOD2 (J18) |                  |                  |                               | Trigger Input [1]     |
|        Zest SMA (J20) |                  |                  |                               | Up Conv. LO helper    |
|       Zest HDMI (J19) |                  |                  | Rear panel I/O                |                       |

## 📖 Citation

If you use this design in your research or projects, please cite our paper:

[1]: [Digital Low-Level RF control system for Accumulator Ring at Advanced Light Source Upgrade Project](https://arxiv.org/abs/2210.05095)

