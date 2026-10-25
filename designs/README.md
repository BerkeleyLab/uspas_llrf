# Accelerator Designs & LLRF Shell Variants

This directory contains the accelerator facility designs: which `llrf_shell` each uses (`SHELL_SRC`), extensions of the register map (`design.py`), and the simulation testbenches.

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
   - **SV shell** (`designs/uspas/llrf_shell.sv`, used by every design): assembles the shared blocks `rx_chain`, `diag`, two `loop_ctrl` (feedback loop with amplitude and phase pulse modulation tables) and `tx_chain` (`llrf_dsp/`, types in `llrf_shell_pkg.sv`) with the design-owned permits, trigger selection, network analyzer and EVR timing. The register map, `uspas_llrf/regmap.py`, declares the rw registers, status words and readback windows; the build generates `_gen/llrf_shell_regs.sv` (registers, mirror, status banks and the readback mux), its package and the whole `llrf_shell.json`. sv2v converts the SV sources, and the result is concatenated with the preprocessed Verilog library into `llrf_shell_expand.v`.
   A design extends the base register map in `designs/<design>/design.py` (LEMP: 1k signal buffers and `iq_buf`). `uspas_llrf/tests/test_regmap.py` checks the result against the step-1 baselines in `_baseline/`.

3. **Unified Cocotb Verification**:
   A common testbench class, `uspas_llrf.tests.test_llrf_shell.TB_llrf_shell`, is used across designs. Each design has its own test runner in `designs/<design>/tb/llrf_shell/` parametrized for its specific frequency set, clock rates, and loopback/feedback channel configurations.

4. **`llrf_shell` Flavors**:
   All designs use the base shell; designs other than uspas point `SHELL_SRC` at it:

| `llrf_shell` Flavor | Base Location | Used By Designs | Key Features |
| :--- | :--- | :--- | :--- |
| **Baseline** | `designs/uspas/llrf_shell.sv` | `uspas`, `alsu`, `lemp`, `awa`, `pip-ii` | Dual-loop PI feedback with amplitude and phase pulse modulation tables (`loopN_amp_mod`, `loopN_phs_mod`, 16k x 18-bit, `2^loopN_pulse_res_shift` clocks per entry), raw/IQ sample buffers packed at `2^SIG_BUF_AW` (2k; LEMP 1k, `designs/lemp/design.py`), standard pulse gating via `pulse_gen`, circular buffer, fast interlocks. |

> **Roadmap**: ALSU and LEMP get their own thin shells over the same blocks (`phase_ramp`; LEMP timing and interlock), see `doc/llrf_shell_unification_plan.md`.

---

## Design Matrix Summary

| Design (`DESIGN`) | Frequency Set (`FSET`) | `llrf_shell` Source | Readback windows | Pulse modulation | Special Features / Operating Mode |
| :--- | :---: | :--- | :--- | :---: | :--- |
| **`uspas`** | `USPAS` | `designs/uspas/llrf_shell.sv` | `regmap.py` | Yes | USPAS 2023 educational setup, CW/Gated |
| **`alsu`** | `ALSU` | `SHELL_SRC` &rarr; `../uspas/llrf_shell.sv` | `regmap.py` | Yes | ALS-U Accumulator Ring LLRF (500 MHz MO) |
| **`lemp`** | `LEMP` | `SHELL_SRC` &rarr; `../uspas/llrf_shell.sv` | `regmap.py` | Yes | SLAC LEMP modernization (2856 MHz MO) |
| **`pip-ii`** | `AWA` | `SHELL_SRC` &rarr; `../uspas/llrf_shell.sv` | `regmap.py` | Yes | Fermilab PIP-II Linac pulse modulation |
| **`awa`** | `AWA` | `SHELL_SRC` &rarr; `../uspas/llrf_shell.sv` | `regmap.py` | Yes | AWA pulsed setup |

