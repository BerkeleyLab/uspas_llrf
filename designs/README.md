# Accelerator Designs & LLRF Shell Variants

This directory contains standalone accelerator facility designs, customized `llrf_shell.v` top-level wrappers, static register maps, and simulation testbenches for different accelerator facilities.

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
   - **SV shell** (`designs/uspas/llrf_shell.sv`, used by uspas, alsu and lemp): assembles the shared blocks `rx_chain`, `diag` and `tx_chain` (`llrf_dsp/*.sv`, types in `llrf_shell_pkg.sv`) with the design-owned permits, trigger selection, feedback loops and EVR timing. The register map, `uspas_llrf/regmap.py`, declares the rw registers, status words and readback windows; the build generates `_gen/llrf_shell_regs.sv` (registers, mirror, status banks and the readback mux), its package and the whole `llrf_shell.json`. sv2v converts the SV sources, and the result is concatenated with the preprocessed Verilog library into `llrf_shell_expand.v`.
   - **Verilog shell** (`llrf_shell.v` in pip-ii, until it moves onto the SV shell): the build generates `_gen/llrf_shell_regs.vh` (register storage, decode and mirror) and the register part of `llrf_shell.json`; status entries come from the `// alias:` comments of the readback mux and the buffer windows from `static_regmap.json`.

   A design extends the base register map in `designs/<design>/design.py` (pip-ii). `uspas_llrf/tests/test_regmap.py` checks the result against the step-1 baselines in `_baseline/`.

3. **Unified Cocotb Verification**:
   A common testbench class, `uspas_llrf.tests.test_llrf_shell.TB_llrf_shell`, is used across designs. Each design has its own test runner in `designs/<design>/tb/llrf_shell/` parametrized for its specific frequency set, clock rates, and loopback/feedback channel configurations.

4. **Matrix of `llrf_shell` Flavors**:
   Currently, 2 flavors are matrixed across all designs; designs that share a shell point `SHELL_SRC` at it:

| `llrf_shell` Flavor | Base Location | Used By Designs | Key Features |
| :--- | :--- | :--- | :--- |
| **Baseline** | `designs/uspas/llrf_shell.sv` | `uspas`, `alsu`, `lemp`, `awa` | Standard dual-loop PI feedback, raw/IQ sample buffers packed at `2^SIG_BUF_AW` (2k; LEMP 1k, `designs/lemp/design.py`), standard pulse gating via `pulse_gen`, circular buffer, fast interlocks. |
| **Pulse Modulation LUT** | `designs/pip-ii/llrf_shell.v` | `pip-ii`, `vts` | Dual arbitrary pulse modulation Look-Up Tables (`pulse0_lut`, `pulse1_lut`, 32k x 16-bit each), `mod_pulse_gen` with configurable sample-rate division (`pulse_res_shift`), pulsed drive modulation. |

> **Future Roadmap**: It is planned to unify all flavors of `llrf_shell.v` into a single, parameterizable top-level shell that natively supports feedforward tables, arbitrary pulse modulation, and configurable buffer structures across all facilities.

---

## Design Matrix Summary

| Design (`DESIGN`) | Frequency Set (`FSET`) | `llrf_shell` Source | Readback windows | Pulse LUT | Special Features / Operating Mode |
| :--- | :---: | :--- | :--- | :---: | :--- |
| **`uspas`** | `USPAS` | `designs/uspas/llrf_shell.sv` | `regmap.py` | No | USPAS 2023 educational setup, CW/Gated |
| **`alsu`** | `ALSU` | `SHELL_SRC` &rarr; `../uspas/llrf_shell.sv` | `regmap.py` | No | ALS-U Accumulator Ring LLRF (500 MHz MO) |
| **`lemp`** | `LEMP` | `SHELL_SRC` &rarr; `../uspas/llrf_shell.sv` | `regmap.py` | No | SLAC LEMP modernization (2856 MHz MO) |
| **`pip-ii`** | `AWA` | `designs/pip-ii/llrf_shell.v` | `designs/pip-ii/static_regmap.json` | **Yes** | Fermilab PIP-II Linac pulse modulation |
| **`awa`** | `AWA` | `SHELL_SRC` &rarr; `../uspas/llrf_shell.sv` | `regmap.py` | No | AWA pulsed setup |

