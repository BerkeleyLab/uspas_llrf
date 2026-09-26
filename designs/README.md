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

2. **Customized `llrf_shell.v` & Static Register Maps**:
   Each design assembles DSP functional blocks from `llrf_dsp/` (DDC, DUC, DDS, PI controllers, circular buffers, interlocks, EVR timing) into a top-level `llrf_shell.v`, accompanied by a `static_regmap.json` specifying static memory and buffer address layouts.

3. **Unified Cocotb Verification**:
   A common testbench class, `uspas_llrf.tests.test_llrf_shell.TB_llrf_shell`, is used across designs. Each design has its own test runner in `designs/<design>/tb/llrf_shell/` parametrized for its specific frequency set, clock rates, and loopback/feedback channel configurations.

4. **Matrix of `llrf_shell.v` Flavors**:
   Currently, 3 flavors of `llrf_shell.v` are matrixed across all designs. Symbolic links (`ln -s`) are used to eliminate duplicate copies across identical implementations:

| `llrf_shell.v` Flavor | Base Location | Used By Designs | Key Features |
| :--- | :--- | :--- | :--- |
| **Baseline** | `designs/uspas/llrf_shell.v` | `uspas`, `alsu`, `lemp`, `awa0` | Standard dual-loop PI feedback, raw/IQ sample buffers (4k/2k samples with `0x1000` stride), standard pulse gating via `pulse_gen`, circular buffer, fast interlocks. |
| **Pulse Modulation LUT** | `designs/awa1/llrf_shell.v` | `awa1`, `pip-ii`, `vts` | Dual arbitrary pulse modulation Look-Up Tables (`pulse0_lut`, `pulse1_lut`, 32k x 16-bit each), `mod_pulse_gen` with configurable sample-rate division (`pulse_res_shift`), pulsed drive modulation. |
| **Compact Buffer Map** | `designs/awa/llrf_shell.v` | `awa` | Similar architecture to `awa1` (compact buffer addresses with `0x800` stride) but without arbitrary pulse modulation LUTs. |

> **Future Roadmap**: It is planned to unify all flavors of `llrf_shell.v` into a single, parameterizable top-level shell that natively supports feedforward tables, arbitrary pulse modulation, and configurable buffer structures across all facilities.

---

## Design Matrix Summary

| Design (`DESIGN`) | Frequency Set (`FSET`) | `llrf_shell.v` Source | `static_regmap.json` Source | Pulse LUT | Special Features / Operating Mode |
| :--- | :---: | :--- | :--- | :---: | :--- |
| **`uspas`** | `USPAS` | `designs/uspas/` | `designs/uspas/` | No | USPAS 2023 educational setup, CW/Gated |
| **`alsu`** | `ALSU` | Symlink &rarr; `../uspas/` | Symlink &rarr; `../uspas/` | No | ALS-U Accumulator Ring LLRF (500 MHz MO) |
| **`lemp`** | `LEMP` | Symlink &rarr; `../uspas/` | Symlink &rarr; `../uspas/` | No | SLAC LEMP modernization (2856 MHz MO) |
| **`awa0`** | `AWA` | Symlink &rarr; `../uspas/` | Symlink &rarr; `../uspas/` | No | AWA baseline pulsed setup |
| **`awa1`** | `AWA` | `designs/awa1/` | `designs/awa1/` | **Yes** | AWA arbitrary pulse modulation (1300 MHz MO) |
| **`pip-ii`** | `AWA` | `designs/pip-ii/` | `designs/pip-ii/` | **Yes** | Fermilab PIP-II Linac pulse modulation |
| **`vts`** | `AWA` | Symlink &rarr; `../awa1/` | Symlink &rarr; `../awa1/` | **Yes** | Fermilab VTS cavity testing (1295 MHz MO) |
| **`awa`** | `AWA` | `designs/awa/` | `designs/awa/` | No | AWA compact buffer addressing without LUT |

---

## Build & Verification Commands

All designs use the centralized `designs/rules.mk` Makefile rules.

```bash
# Build expanded Verilog and merged register map JSON for a single design
cd designs/uspas && make
cd designs/awa1 && make

# Build all designs
cd designs && make

# Run CDC (Clock Domain Crossing) check via Yosys
cd designs/uspas && make llrf_shell_expand.v && make llrf_shell_cdc.txt

# Run cocotb simulation for a specific design
cd designs/uspas/tb/llrf_shell && make
cd designs/alsu/tb/llrf_shell && make
cd designs/awa1/tb/llrf_shell && make

# Clean build artifacts
cd designs/uspas && make clean
cd designs && make clean
```
