# LLRF Firmware for USPAS 2023

This repository holds the firmware for USPAS 2023 LLRF course, on the [Marble](https://github.com/BerkeleyLab/Marble) and [Zest](https://github.com/BerkeleyLab/Zest) platform. The design originated from the LLRF system for the ALS-U Accumulator Ring, LBNL.

## Global DSP frequency settings

Each design (`DESIGN`) runs with one of the frequency sets (`FSET`) below. [settings.mk](settings.mk) maps `DESIGN` to `FSET` and sets the DSP clock; [uspas_llrf/settings.json](uspas_llrf/settings.json) holds the DSP and cavity parameters of each `FSET`. The designs, their shells and chassis I/O are described in [designs/README.md](designs/README.md).

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
Details see [Digital Low-Level RF control system for Accumulator Ring at Advanced Light Source Upgrade Project](https://arxiv.org/abs/2210.05095).

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

Details see [Digital Low-Level RF system for the Linac Electronics Modernization Plan at LCLS](https://arxiv.org/abs/2510.11950),
and [LEMP LLRF Firmware and Software](https://indico.jlab.org/event/939/contributions/17411/).

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

Details see [LLRF system upgrade of Argonne Wakefield Accelerator Facility](https://indico.jlab.org/event/939/contributions/17433/).
<!--
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

The Zest reference clock is LO. -->

## 🚀 Quick Start

### LLRF DSP and verification

See [doc/README.md](doc/README.md). Run DSP unit tests:

```bash
pip install -e .
make -C llrf_dsp/tests
```


### Synthesize bitstream

```bash
make -C top/{DESIGN}
```
Where DESIGN is alsu, awa, lemp, uspas or pip-ii. Each design builds in its own
directory, so designs can be built side by side. The shared rules are in
[top/common](top/common/top_rules.mk); per-design SoC firmware settings are in `soc/{DESIGN}/`.

### Program bitstream to hardware

Provide the Zest reference clock signal at specified frequency in the above list, at +3dBm.

```bash
make -C top/{DESIGN} system_config MARBLE_SERIAL=42 BITSTREAM=<bitstream>.bit
```
Note 42 is the Marble serial number.

### Run dashboard

After programming the bitstream file, Marble should be reachable by pinging its IP address [e.g. 192.168.19.42].
A web based dashboard is available to show its dashboard:

```bash
pip install -e .
python -m uspas_llrf.app.dash --addr 192.168.19.42:803 --conf USPAS
```
`--conf` is the design's `FSET` (USPAS, ALSU, LEMP or AWA).

### Boot-load soft core program

See [soc/common/synth](soc/common/synth/README.md).

### Serial console

```bash
make -C top/{DESIGN} console MARBLE_SERIAL=42
```
The SoC console on the Marble's USB UART; see [doc/developer_guide.md](doc/developer_guide.md) for the reset-on-close behavior and the udev rule.

### Chassis I/O

The Marble / Zest connections of each design are listed in [designs/README.md](designs/README.md#chassis-io).

## 📖 Citation

If you use this design in your research or projects, please cite our paper:

[1]: [Digital Low-Level RF control system for Accumulator Ring at Advanced Light Source Upgrade Project](https://arxiv.org/abs/2210.05095)

