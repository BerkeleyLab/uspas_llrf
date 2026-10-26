# Accelerator Designs & LLRF Shell Variants

This directory contains the accelerator facility designs: which `llrf_shell` each uses (`SHELL_SRC`), extensions of the register map (`design.py`), design-specific RTL (ALSU `phase_ramp.v`; LEMP `fiducial_int_gen.v`, `triggers.v`, `timing_core_local.v`, with their unit tests in `designs/lemp/tb/`), and the simulation testbenches. The top level and SoC firmware of each design are in `top/<design>/` and `soc/<design>/`.

---

## Key Concepts

1. **Frequency Configurations (`FSET`)**:
   Every design operates using one of four fundamental frequency configurations:
   - **`USPAS`**: 115 MHz DSP clock, 20 MHz IF (IF/Fs = 4/23)
   - **`ALSU`**: 114.674 MHz DSP clock, 41.699 MHz IF (IF/Fs = 4/11)
   - **`LEMP`**: 119 MHz DSP clock, 25.5 MHz IF (IF/Fs = 3/14)
   - **`AWA`**: 94.286 MHz DSP clock, 20 MHz IF (IF/Fs = 7/33), 2nd Nyquist TX (145 MHz IF)

   The mapping from `DESIGN` to `FSET` is configured in `settings.mk` and parameter sets in `uspas_llrf/settings.json`.

2. **Design shells and the register map**:
   Each design has a top-level `llrf_shell`, selected by `SHELL_SRC` in its Makefile:
   - **SV shell** (`designs/uspas/llrf_shell.sv`, used by every design): assembles the shared blocks `rx_chain`, `diag`, `loops` (two `loop_ctrl`: feedback loops with amplitude and phase pulse modulation tables) and `tx_chain` (`llrf_dsp/`, types in `llrf_shell_pkg.sv`) with the design-owned permits, trigger selection, network analyzer and EVR timing. The register map, `uspas_llrf/regmap.py`, declares the rw registers, status words and readback windows; the build generates `_gen/llrf_shell_regs.sv` (registers, mirror, status banks and the readback mux), its package and the whole `llrf_shell.json`. The registers of a block instance (`Reg(..., inst='arc')`) reach the block as one config struct, `cfg_dsp.arc` of type `arc_cfg_t` from `llrf_shell_pkg.sv`; `monitor_inlk`, `arc_inlk` and `ntw_analyzer` take it as `input <inst>_cfg_t cfg`, and `loops` takes the per-loop registers `loopN_*` as `cfg_dsp.loop[N]` (`loop_cfg_t`). sv2v converts the SV sources, and the result is concatenated with the preprocessed Verilog library into `llrf_shell_expand.v`.
   A design extends the base register map in `designs/<design>/design.py` (LEMP: 1k signal buffers and `iq_buf`). `uspas_llrf/tests/test_regmap.py` checks the result against the step-1 baselines in `_baseline/`.

3. **Unified Cocotb Verification**:
   A common testbench class, `uspas_llrf.tests.test_llrf_shell.TB_llrf_shell`, is used across designs. Each design has its own test runner in `designs/<design>/tb/llrf_shell/` parametrized for its specific frequency set, clock rates, and loopback/feedback channel configurations.

4. **`llrf_shell` Flavors**:
   All designs use the base shell; designs other than uspas point `SHELL_SRC` at it:

| `llrf_shell` Flavor | Base Location | Used By Designs | Key Features |
| :--- | :--- | :--- | :--- |
| **Baseline** | `designs/uspas/llrf_shell.sv` | `uspas`, `alsu`, `lemp`, `awa`, `pip-ii` | Dual-loop PI feedback with amplitude and phase pulse modulation tables (`loopN_amp_mod`, `loopN_phs_mod`, 16k x 18-bit, `2^loopN_pulse_res_shift` clocks per entry), raw/IQ sample buffers packed at `2^SIG_BUF_AW` (2k; LEMP 1k, `designs/lemp/design.py`), standard pulse gating via `pulse_gen`, circular buffer, fast interlocks. |

> **Roadmap**: LEMP gets its own shell over the same blocks (fiducial and trigger selection, LEMP timing, SSSB, interlock; plan step 9c, with the LEMP top level and SoC in 9e). An ALSU shell with `phase_ramp` is deferred (step 7e). See `doc/llrf_shell_unification_plan.md`.

---

## Design Matrix Summary

| Design (`DESIGN`) | Frequency Set (`FSET`) | `llrf_shell` Source | Readback windows | Pulse modulation | Special Features / Operating Mode |
| :--- | :---: | :--- | :--- | :---: | :--- |
| **`uspas`** | `USPAS` | `designs/uspas/llrf_shell.sv` | `regmap.py` | Yes | USPAS 2023 educational setup, CW/Gated |
| **`alsu`** | `ALSU` | `SHELL_SRC` &rarr; `../uspas/llrf_shell.sv` | `regmap.py` | Yes | ALS-U Accumulator Ring LLRF (500 MHz MO) |
| **`lemp`** | `LEMP` | `SHELL_SRC` &rarr; `../uspas/llrf_shell.sv` | `regmap.py` | Yes | SLAC LEMP modernization (2856 MHz MO) |
| **`pip-ii`** | `AWA` | `SHELL_SRC` &rarr; `../uspas/llrf_shell.sv` | `regmap.py` | Yes | Fermilab PIP-II Linac pulse modulation |
| **`awa`** | `AWA` | `SHELL_SRC` &rarr; `../uspas/llrf_shell.sv` | `regmap.py` | Yes | AWA pulsed setup |

---

## Chassis I/O

The connections of miscellaneous signals to the Marble / Zest IO ports. The base top level (`top/common/`) routes the four PMODs through the SoC, whose firmware selects the trigger input and output pins per `FSET` (`soc/common/system.c`); a design that owns a PMOD drives it from `top/<design>/design_mid.vh` instead (`DESIGN_OWNS_PMOD1`/`PMOD2`).

| | **USPAS** | **ALSU** | **LEMP** (LEMP branch, see note) | **AWA** (`FSET` AWA) |
|----------------------:|:-----------------------------:|:---------------------------:|:-----------------------------:|:------------------------------:|
| Marble MMC PMOD (J16) | Front panel OLED | Front panel OLED | Front panel OLED | |
| Marble PMOD1 (J12) | Trigger input [0], output [1] | ARC detectors | Trigger output, interlock I/O | |
| Marble PMOD2 (J13) | | Interlock I/O (FO board) | | Front panel LED |
| Marble QSFP2 Ch.1 | | Timing EVR | Timing EVR | |
| Zest PMOD1 (J17) | | Modbus RTU [3:0] | | Up converter enable [7:6] |
| Zest PMOD2 (J18) | | | | Trigger input [1] |
| Zest SMA (J20) | | | | Up converter LO helper (LMK output) |
| Zest HDMI (J19) | | | Rear panel I/O | |

Sources: USPAS and AWA trigger pins and up converter enables in `soc/common/system.c`; ALSU in `top/alsu/design_mid.vh`; the AWA J20 clock in `soc/awa/init_zest.c`. The EVR receiver on QSFP2 Ch.1 is in every design's top level; only ALSU and LEMP use it.

Note: the LEMP column is the deployed LEMP branch (`top/marble_zest` there). On main, `lemp` still uses the base top level until its own `top/lemp/` (plan step 9e).
