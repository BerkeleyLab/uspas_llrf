# RTL and Physics Co-Simulation for LLRF

## Getting started

1. Install [`cocotb`](https://docs.cocotb.org/en/stable/install.html) (tested version: 1.8.1) and ['verilator`](https://verilator.org/guide/latest/install.html) (tested version: 5.018);
2. Build and run simulation:
   ```
   make
   ```
3. Check waveform:
   ```
   gtkwave dump.fst dump.gtkw
   ```