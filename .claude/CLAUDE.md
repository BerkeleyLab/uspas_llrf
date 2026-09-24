# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

# Run all DSP cocotb tests (dds, ddc, duc, llrf_dsp, cic_waves, llrf_shell, pulse_gen)
make

# Run a single cocotb test suite (from llrf_dsp/tests/<suite>)
cd tests/dds && make
cd tests/ddc && make
cd tests/duc && make
cd tests/llrf_dsp && make
cd tests/cic_waves && make
cd tests/llrf_shell && make
cd tests/pulse_gen && make

# Build standalone design package / IP artifacts (e.g., uspas, pip-ii, awa1, etc.)
cd ../designs/uspas && make
cd ../designs/pip-ii && make

# Enable waveform tracing (generates FST/VCD)
make WAVES=1

# Run with Icarus Verilog instead of Verilator
make SIM=icarus

# Run Clock Domain Crossing (CDC) check via Yosys
make llrf_shell_expand.v && make llrf_shell_cdc.txt
```

### 3. Board Support Package (BSP) Test
```bash
cd marble_bsp
make
```

### 4. RISC-V SoC Simulation
```bash
# Open-source RTL simulation (Icarus Verilog)
cd soc/marble_zest/sim
make

# Full simulation with Vivado UNISIM primitives (requires Vivado in PATH)
cd soc/marble_zest/top_sim
make
```

### 5. FPGA Bitstream Synthesis
```bash
cd top/marble_zest
# TARGET choices: USPAS, ALSU, LEMP, AWA; facility choices: uspas, alsu, lemp, awa, pip-ii, vts
make FSET=USPAS facility=uspas
```

### 6. Hardware Deployment & Testing (LEEP)
```bash
cd top/marble_zest

# Program FPGA over OpenOCD (set MARBLE_SERIAL to the board's serial number)
make system_config MARBLE_SERIAL=122 FSET=USPAS

# Test Ethernet and system self-test via LEEP (IP defaults to 192.168.19.<SERIAL>)
make system_test MARBLE_SERIAL=122

# Direct LEEP CLI access
.venv/bin/leep leep://192.168.19.122:803 list
.venv/bin/leep leep://192.168.19.122:803 reg <reg_name>
.venv/bin/leep leep://192.168.19.122:803 reg <reg_name>=<val>
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
│   └── settings.json          # Pre-defined facility LLRF DSP configuration parameters
├── designs/                   # Standalone facility designs and static register maps (alsu, awa, awa0, awa1, lemp, pip-ii, uspas, vts)
├── llrf_dsp/                  # Verilog DSP core & subsystems
│   ├── tests/                 # Cocotb testbenches verifying DSP modules
│   ├── dds.v, ddc.v, duc.v    # NCO / Direct Digital Synthesis, Non-IQ Down-Converter, Up-Converter
│   ├── dsp_core.v             # Baseband PI feedback controller with CORDIC polar/rectangular transforms
│   ├── cic_waves.v            # CIC decimation filters, multi-channel circular waveform capture buffer & fast interlocks
│   └── llrf_shell.v           # Top-level DSP integration shell connecting localbus, ADCs, DACs, and feedback loops
├── marble_bsp/                # Marble FPGA board support package (Local Bus, Packet Badger UDP/Ethernet, EVR timing, MMC)
├── soc/marble_zest/           # PicoRV32 RISC-V soft-core SoC for configuration, booting, and diagnostics
├── top/marble_zest/           # Top-level FPGA integration (`marble_zest_top.v`) and Vivado synthesis flow
├── epics/                     # EPICS Display Builder UI screens (BOB files)
└── doc/                       # System documentation and Jupyter demonstration notebooks
```

### Key Architectural Concepts:
1. **IQ Convention**: Signals use positive carrier frequency: $y(t) = \Re((I + jQ) e^{j\omega t}) = I\cos(\omega t) - Q\sin(\omega t)$.
2. **Clocking Structure**:
   - $f_{\text{dac\_clk}} = 2 f_{\text{adc\_clk}} = 2 f_{\text{dsp\_clk}}$
   - The reference clock feeds a clock distributor (LMK01801) driving ADCs (AD9653) and DACs (AD9781).
3. **Control Interface**: Registers and circular buffers are memory-mapped through LBNL Local Bus and exposed over Ethernet UDP using LBNL Packet Badger and the `leep` Python library/CLI.
4. **Facility Configurations**: Different accelerator facilities (USPAS, ALSU, LEMP, AWA, VTS) have different IF, LO, and RF frequencies defined in [settings.mk](settings.mk) and [uspas_llrf/settings.json](uspas_llrf/settings.json). Use `make facility=<name>` in `llrf_dsp/` or `FSET=<TARGET>` in `top/marble_zest/` to select the target configuration.
