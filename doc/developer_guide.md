# Developer's Guide

This file provides guidance to developers when working with code in this repository.

## Environment & Python Virtual Environment

Always use the local virtual environment at `.venv/` (Python 3.13):
```bash
# Run python commands / pytest using .venv
.venv/bin/python <script>
.venv/bin/pytest
```

Required system & FPGA tools:
- **Verilator** (v5.038+ tested) or **Icarus Verilog** (v12.0 tested)
- **cocotb** (v2.0.1)
- **Yosys** (for synthesis & CDC checks)
- **Xilinx Vivado 2022.1+** (for bitstream synthesis and `top_sim`)
- Submodules: LBNL `submodules/bedrock` (must be initialized: `git submodule update --init --recursive`)

---

## Common Development Commands

### 1. Python & Linting
```bash
# Install package in editable mode
.venv/bin/python -m pip install -e .

# Run pytest
.venv/bin/pytest

# Code style checking (per CI)
flake8 uspas_llrf llrf_dsp/tests
```

### 2. LLRF DSP Verification & Cocotb Simulation
The DSP testbenches use cocotb with Verilator (default) or Icarus Verilog.

```bash
cd llrf_dsp

# Run DSP core subsystem cocotb tests (dds, ddc, duc, llrf_dsp, cic_waves, pulse_gen)
make

# Run a single cocotb test suite for DSP submodules (from llrf_dsp/tests/<suite>)
cd tests/dds && make
cd tests/ddc && make
cd tests/duc && make
cd tests/llrf_dsp && make
cd tests/cic_waves && make
cd tests/pulse_gen && make

# Build standalone design package / IP artifacts (e.g., uspas, pip-ii, awa, etc.)
cd ../designs/uspas && make
cd ../designs/awa && make
# Or build all designs at once
cd ../designs && make

# Run unified llrf_shell cocotb simulation for a specific design
cd ../designs/uspas/tb/llrf_shell && make
cd ../designs/alsu/tb/llrf_shell && make
cd ../designs/awa/tb/llrf_shell && make
cd ../designs/lemp/tb/llrf_shell && make

# Enable waveform tracing (generates FST/VCD)
make WAVES=1

# Run with Icarus Verilog instead of Verilator
make SIM=icarus

# Run Clock Domain Crossing (CDC) check via Yosys for a specific design
cd ../designs/uspas && make llrf_shell_expand.v && make llrf_shell_cdc.txt
```

### 3. Board Support Package (BSP) Test
```bash
cd marble_bsp
make
```

### 4. RISC-V SoC Simulation
```bash
# Open-source RTL simulation (Icarus Verilog)
cd soc/common/sim
make

# Full simulation with Vivado UNISIM primitives (requires Vivado in PATH)
cd soc/common/top_sim
make
```

### 5. FPGA Bitstream Synthesis
```bash
# One directory per design: top/{uspas, alsu, lemp, awa, pip-ii}, each with its own _xilinx/
# (FSET is automatically mapped from DESIGN in settings.mk: USPAS, ALSU, LEMP, AWA)
# Shared rules: top/common/top_rules.mk; SoC firmware is built in soc/<design>/build/
make -C top/uspas
make -C top/awa
```

### 6. Hardware Deployment & Testing (LEEP)
```bash
cd top/uspas

# Program FPGA over OpenOCD (set MARBLE_SERIAL to the board's serial number)
make system_config MARBLE_SERIAL=61

# Test Ethernet and system self-test via LEEP (IP defaults to 192.168.19.<SERIAL>)
make system_test MARBLE_SERIAL=61

# Direct LEEP CLI access
.venv/bin/leep leep://192.168.18.61:803 list
.venv/bin/leep leep://192.168.18.61:803 reg <reg_name>
.venv/bin/leep leep://192.168.18.61:803 reg <reg_name>=<val>
```

---

## High-Level Architecture & Codebase Structure

This repository contains the digital Low-Level RF (LLRF) firmware/gateware suite targeting the LBNL **Marble** FPGA carrier (Kintex-7) and **Zest** digitizer (FMC board).

```
uspas_llrf/
├── submodules/bedrock/        # LBNL Bedrock gateware library (localbus, CORDIC, badger Ethernet, RISC-V PicoRV32)
├── uspas_llrf/                # Python package
│   ├── model/                 # DSP analytical models (llrf_dsp.py, plant.py, cavity.json) used in cocotb & Python drivers
│   ├── app/                   # High-level Python application interfaces and BSP drivers
│   ├── tools/                 # Hardware utility scripts (RF synth, EVG generator)
│   ├── tests/                 # Unified testbench classes (test_llrf_shell.py: TB_llrf_shell)
│   └── settings.json          # Pre-defined facility LLRF DSP configuration parameters
├── designs/                   # Standalone facility designs, customized llrf_shell.v, static regmaps, and testbenches
│   ├── rules.mk               # Centralized make rules for all designs (expansion, JSON merge, CDC checks)
│   ├── README.md              # Detailed overview of design variants and frequency configuration matrix
│   ├── uspas/                 # Baseline llrf_shell.v and static register map
│   ├── alsu/, lemp/           # Designs symlinking baseline uspas/llrf_shell.v and static_regmap.json
│   ├── pip-ii/                # Designs with arbitrary pulse modulation LUT support (pip-ii/llrf_shell.v)
│   └── awa/                   # Design with compact buffer address layout (awa/llrf_shell.v)
├── llrf_dsp/                  # Verilog DSP core & submodules (DDC, DUC, DDS, PI scalar, CIC filters, interlocks)
│   ├── tests/                 # Cocotb testbenches verifying individual DSP submodules
│   ├── dds.v, ddc.v, duc.v    # NCO / Direct Digital Synthesis, Non-IQ Down-Converter, Up-Converter
│   ├── dsp_core.v             # Baseband PI feedback controller with CORDIC polar/rectangular transforms
│   ├── cic_waves.v            # CIC decimation filters, multi-channel circular waveform capture buffer & fast interlocks
│   └── pulse_gen.v            # Trigger and gating pulse generation
├── marble_bsp/                # Marble FPGA board support package (Local Bus, Packet Badger UDP/Ethernet, EVR timing, MMC)
├── soc/
│   ├── common/                # PicoRV32 RISC-V soft-core SoC (system.v, firmware, sim/, top_sim/, synth/)
│   └── <design>/              # Per-design firmware: design.mk, settings_design.h, init_zest.c, init_marble.c
├── top/
│   ├── common/                # Top-level FPGA integration (`marble_zest_top.v`), top_rules.mk, Vivado TCL, topsim
│   └── <design>/              # Per-design build directory (Makefile; optional design_io.vh, design_mid.vh)
├── epics/                     # EPICS Display Builder UI screens (BOB files)
└── doc/                       # System documentation and Jupyter demonstration notebooks
```

### Key Architectural Concepts:
1. **IQ Convention**: Signals use positive carrier frequency: $y(t) = \Re((I + jQ) e^{j\omega t}) = I\cos(\omega t) - Q\sin(\omega t)$.
2. **Clocking Structure**:
   - $f_{\text{dac\_clk}} = 2 f_{\text{adc\_clk}} = 2 f_{\text{dsp\_clk}}$
   - The reference clock feeds a clock distributor (LMK01801) driving ADCs (AD9653) and DACs (AD9781).
3. **Control Interface**: Registers and circular buffers are memory-mapped through LBNL Local Bus and exposed over Ethernet UDP using LBNL Packet Badger and the `leep` Python library/CLI.
4. **Facility Configurations & Entry Key**:
   - The top-level entry key for synthesis and build configuration is `DESIGN` (`uspas`, `alsu`, `lemp`, `awa`, `pip-ii`).
   - `DESIGN` automatically maps to `FSET` (`USPAS`, `ALSU`, `LEMP`, `AWA`) in `settings.mk` and `uspas_llrf/settings.json`.
5. **LLRF Shell Flavors & Consolidation**:
   - 3 consolidated flavors of `llrf_shell.v` are matrixed across designs:
     - **Baseline** (`designs/uspas/llrf_shell.v`): Used by `uspas`, `alsu`, `lemp` (`alsu/` and `lemp/` symlink `llrf_shell.v` and `static_regmap.json` to `uspas/`).
     - **Pulse Modulation LUT** (`designs/pip-ii/llrf_shell.v`): Used by `pip-ii` with arbitrary pulse LUTs (`pulse0_lut`, `pulse1_lut`).
     - **Compact Buffer Map** (`designs/awa/llrf_shell.v`): Used by `awa` with compact buffer address stride (`0x800`); a separate file, not a symlink, with its own `static_regmap.json`.
   - Unified cocotb testbench `uspas_llrf.tests.test_llrf_shell.TB_llrf_shell` verifies all designs in `designs/<design>/tb/llrf_shell/`.
   - Planned roadmap: Unify all flavors into a single parameterizable `llrf_shell.v` supporting feedforward tables and pulse modulation across all facilities.
6. **Analog Frontend TX Spectral Flip**: Supports `tx_afe_spectral_flip` XORed with `duc_spectral_flip` for hardware RF mixing polarity compensation.
