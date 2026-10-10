# llrf_shell Unification & SystemVerilog Architecture Plan

Status: draft v9. All review questions resolved (D1–D22); v8 and v9 revise D1 after LEMP review (LEMP keeps 1K signal buffers and its one-call `iq_buf` readout). newad retired for llrf_shell (D14); sv2v in the flow (D15); per-design `top/` and `soc/` (D16, D20); ALSU merge-back (D17–D19, D21–D22).
Scope: `designs/*/llrf_shell.v`, `static_regmap.json`, `llrf_dsp/`, `uspas_llrf/model/llrf_shell.py`, `uspas_llrf/tests/test_llrf_shell.py`, and LEMP branch `llrf_dsp/llrf_shell.v`.

## D. Decisions (from review)

| # | Decision |
|---|---|
| D1 | `SIG_BUF_AW = 11` (2048 samples) for every design **except LEMP, which keeps `SIG_BUF_AW = 10`** (1024 samples, as on the LEMP branch; revised in v8 after LEMP review). uspas/alsu go from 4K to 2K; awa/pip-ii stay at 2K. `designs/lemp` on main is a uspas symlink until step 9 and follows uspas until then. Signal buffers are packed at their natural size (`2^SIG_BUF_AW`), so the 20 I/Q buffers always form one contiguous region; LEMP keeps its `iq_buf` window over it (`addr_width` 15, v9). The 2K designs keep the §1.1 map; only LEMP's buffer addresses differ. |
| D2 | Pulse-modulation LUTs are in **every** design. No `PULSE_LUT_EN`. |
| D3 | Modulation is indexed from the **pulse start**, is **additive**, and applies to **both amplitude and phase** per loop. LUT memory uses bedrock `dsp/dpram.v`. |
| D4 | A Python allocator is the source of truth for the address map. |
| D5 | No clients use hard-coded addresses; leep resolves names. Address moves are free. |
| D6 | Assembly is split into the blocks `rx_chain`, `loop_ctrl` (including modulation), `tx_chain`, `diag` and `lb_rd_mux`. |
| D7 | `designs/<d>/` stays as the place for per-design customization. LEMP's shell, which today lives only on the LEMP branch, is merged back as `designs/lemp`. |
| D8 | Phase LUT entries are 18-bit, in raw `phs_setpoint` units (full ±180°). |
| D9 | LEMP's `loopN_phs_shift`/`loopN_phs_shift_delay` are **kept**, with names unchanged. They coexist with the phase LUT. |
| D10 | 16K entries per LUT (stretched by `2^res`) is enough. |
| D11 | **LEMP register naming** is adopted for all designs: `drvN_pulse_mode` and `soft_driveN_enable` replace `pulse_modes` and `soft_drive_enable`; loop-scoped regs use the `loopN_` prefix. |
| D12 | `timing_core_local`, `fiducial_int_gen` and `triggers` stay **LEMP-only**, under `designs/lemp/`. |
| D13 | `LEMP_bypass` (and the other `LEMP_*` branches) is deferred. |
| D14 | **newad is retired for `llrf_shell`.** A Python generator produces the register file, the SV package and `llrf_shell.json` (§2.4). `marble_bsp` keeps newad. |
| D15 | **sv2v (v0.0.13) is installed.** `llrf_shell_expand.v` becomes the sv2v output, consumed by Vivado, Yosys CDC and (optionally) Icarus. |
| D16 | **`top/<design>/`** per design, on a shared `top/common/` base, for top-level IO mapping, extra IP, constraints and synthesis settings (§2.8). |
| D17 | **ALSU (`alsu_fork`) is merged back early** (step 3). ALSU keeps the uspas base shell; its differences go to `top/alsu/` and `soc/alsu/` (§3.2). |
| D18 | The **upgraded `arc_inlk`** (ARC detector test/reset strobes, 0.5 s pulse) is adopted in the shared `diag` block for **all** designs. |
| D19 | **`phase_ramp` stays ALSU-specific and unchanged** in `designs/alsu/`: loop 0 only, started by an **EVR** event, cleared when the loop opens (same as today). The ALSU shell wires it into `loop_ctrl` through the generic `phs_offset` hook. A ramp source inside a generic loop modulator is **future work** (§1.2.1). |
| D20 | **Per-design SoC:** `soc/common/` + `soc/<design>/`, with a `system.v` expansion port for design peripherals (ALSU Modbus UART1) (§2.9). |
| D21 | **Register naming convention** (§2.4.1): loop-scoped registers use `loopN_<func>_<field>`, extending D11. ALSU's `phase_ramp_*` becomes `loop0_phs_ramp_*`, and `designs/alsu/scripts/phase_ramp.py` is updated. |
| D22 | `BLOCK_RAM_SIZE=65536` is **ALSU-only** (`soc/alsu/design.mk`). Other designs keep 32768. |

---

## 0. Inventory of variants

### 0.1 Main branch: uspas / awa / pip-ii

| Aspect | uspas (alsu, lemp symlink to it) | awa | pip-ii |
|---|---|---|---|
| `SIG_BUF_AW` | 12 | 11 | 11 |
| ADC raw bufs | `0x12000`–`0x19fff` | `0x12000`–`0x15fff` | `0x12000`–`0x15fff` |
| `dac0/1_raw_out` | — | `0x16000`–`0x16fff`, hard-wired 0 | — |
| IQ bufs (I then Q, 10 each) | `0x1c000`–`0x2ffff` | `0x17000`–`0x20fff` | `0x16000`–`0x1ffff` |
| Pulse LUTs | — | — | `pulse0_lut` `0x20000`, `pulse1_lut` `0x28000`, each 32K×16 |
| Extra newad regs | — | — | `lut0_len`, `lut1_len`, `pulse_res_shift`, `pulse_modulation_enable` |

Apart from these, the files are identical except for cosmetics: `&` vs `&&` on 1-bit `inlk_arc_permit`, and `sig_buf_transferred` declared `[N_CH-1:0]` where `[N_ADC-1:0]` is correct.

### 0.2 LEMP branch (`origin/LEMP`, 449 ahead / 42 behind main)

Changes to `llrf_dsp/llrf_shell.v` relative to the merge-base:

| Area | LEMP change | Category |
|---|---|---|
| RX | ADC ch 6, 7 are **DC-coupled**: raw ADC `<< (DWBB-DW)` goes to the sig/cic buffers, bypassing the DDC; the loop field select still uses DDC data | rx_chain variant |
| Buffers | `SIG_BUF_AW=10`. `buf_delay` reg delays the sig_buf and cic capture after the trigger | diag (generic) |
| Loop | Per-loop `loopN_phs_shift` and `loopN_phs_shift_delay`: a phase step added to `phs_setpoint` from `pulse_start + delay` to the pulse end | kept in LEMP shell (D9) |
| Pulse | `loopN_pulse_start` is 32-bit, `pulse_gen` AW=32. `pulse_modes`/`soft_drive_enable` split into `drvN_pulse_mode`/`soft_driveN_enable` | naming adopted everywhere (D11) |
| Interlock | New ports `intlk_latch_in[7:0]` and `intlk_trig_in`. `dac_permit_int` is cleared by any latch and re-armed on a fiducial edge, and drives `drive_on` in place of `soft_drive_enable` | design-specific |
| Timing | `timing_core_local` (4 hard-coded DSP events 151/152/1/10) replaces `timing_core`; HB/PPS/OC status is dropped. `fiducial_int_gen` adds `fiducial_sel`, `event_sel` and acc/stb delays | LEMP-only, `designs/lemp/` (D12) |
| Triggers | `pmod_trigs[3:0]` from `triggers.v` × 4 using newad `// auto(ix_t,4)` per-instance registers. Gated by the interlock latch | LEMP-only, `designs/lemp/` (D12) |
| Trig select | `WAVE_TRIG_*` encoding **renumbered** (ALWAYS=0, INT=4, EVR=7, versus main's INT=0, ALWAYS=4, EVR=3). `cic_waves` gets `wave_trig_sel`/`buf_trig` ports | conflict |
| I/O | Adds `dds_reset_out`, `dds_cos/sin`, `sssb_*`, `fiducial_ext`, `evr_events`, plus `` `AUTOMATIC_map `` | design-specific |
| Readback | `reg_bank_1` is reassigned (dsp clk freq, sssb, EVR event freqs, acc/stb cycles) | design-specific |

Issues seen in the LEMP delta, to fix while porting:

| # | Issue |
|---|---|
| L1 | DC channels: `sig_iq_flat` puts the ADC sample in the **Q** slot (I=0), but `sig_i/q_buf` put it in **I**. The CIC and sig buffers therefore disagree. Pick I=ADC, Q=0. |
| L2 | `wave_trig_sel` is an lb1 (dsp-domain) newad reg, but it is passed through `data_xdomain` as if it came from lb_clk. The crossing is redundant, and its `clk_in` is wrong. |
| L3 | Blocking assignments (`trig_rsts_n = 0`) inside `always @(posedge dsp_clk)`. |
| L4 | `WAVE_TRIG_*` renumbering breaks the shared Python `WaveTrigSel` enum. Use one encoding and add `Fiducial` as a new value rather than renumbering. |
| L5 | `pulse_high_len - phs_loop_shift_delay` underflows when the delay exceeds the pulse length. Fix: compute the step in the LEMP shell from `loop_ctrl`'s `pulse_idx` (`pulse_dval && idx >= delay`), instead of running a second `pulse_gen` on `high_len - delay`. |

### 0.3 ALSU branch (`alsu_fork`, 2 ahead / 0 behind main)

`alsu_fork` is the current state of the deployed ALSU LLRF. It is a merge-back from the separate `alsu-llrf-marble` fork. It does **not** change any `designs/*/llrf_shell.v`: ALSU still uses the uspas base shell.

| Area | ALSU change | Category |
|---|---|---|
| `llrf_dsp/arc_inlk.v` | ARC detector **test and reset**: `test_arc_dev` level becomes `test_mask` plus a `test_stb` strobe; `reset_arc_dev` becomes a strobe; both drive `dev_test_out`/`dev_reset_out` for a fixed **0.5 s** (`F_CLK` param). Has `arc_inlk_tb.v` | shared block, all designs (D18) |
| `llrf_dsp/phase_ramp.v` | **Phase ramp function generator** (not yet instantiated in any shell): on a `ramp_start` edge, steps the phase setpoint by `rate`, `steps` times. Each step waits until \|`err_phs`\| < `error_threshold` for 8 clocks, then dwells `ttime` clocks. 10 s timeout. Has `phase_ramp_tb.v` and `test_scripts/phase_ramp.py` (expects `phase_ramp_*` regs) | ALSU-only, `designs/alsu/`, as-is (D19) |
| `llrf_shell_skin.v` | Adds `fast_rf_permit_out` and `evg_permit_out` (already shell ports) to the CDC skin | shared fix |
| top | `marble_zest_mid.vh`: **PMOD1 → ARC detectors** (`permit_in`=[6:4], `test`=[2:0], `reset`=[3]); **PMOD2 → FO board** (`drive_permit_in`=[7], `slow_permit_in`=[6], `fast_permit_out`=[3], `fast_rf_permit_out`=[2], `evg_permit_out`=[1], `hpa_permit_out`=[0]); PMOD1/2 disconnected from `system` | `top/alsu/` (D16) |
| SoC HW | `system.v`: **UART1 Modbus-RTU** (`rs485_uart` from `submodules/modbus_mockup`) at `BASE_UART1=0x06000000`, IRQ 4, hard-wired to system `PMOD2[3:0]` (= board `ZEST_PMOD1`) | `soc/alsu/` + expansion port (D20) |
| SoC FW | Modbus client (`init_modbus.c`, `mb_client.c`); register map generated from `mb_addr_map.toml` by `modbusAddrMap.py`; `BLOCK_RAM_SIZE` 32K → 64K; `ZEST_BYPASS_AD7794_READS`; main loop timing changed | `soc/alsu/` (D20) |
| SoC tools | `localBusAddressMap.py` replaces `localbus_address_map.py` (array regs unrolled to `name_<i>`; `llrf.c` uses `MON_PHS_0`, `DSP_SLOW_ADC_MIN_0`); `gen_init_reg.py` `sizeof` fix | shared, all designs |
| Repo | `.gitmodules` + `modbus_mockup`; `dir_list.mk` `MB_MOCKUP_DIR`; `pyproject.toml` (`leep>=1.0.0`, `pymodbus`, `tomli`); bedrock bump; `test_scripts/` (Modbus, AD board, phase ramp); demo notebooks | shared / `designs/alsu/scripts/` |
| CI | `.gitlab-ci.yml` matrix reduced to `[alsu]`; other `*_run` jobs disabled | **do not merge**; replaced by a per-design matrix |

**Coupling to the register map:** `mb_addr_map.toml` refers to registers by leep name. Two kinds of names need care:
- names newad derives from instance names: `arc_reset_latch`, `arc_reset_arc_dev`, `arc_test_mask`, `arc_test_stb`, `inlk_amp_hi`, `inlk_inlk_mode`, `inlk_reset_inlk`
- reg-bank aliases: `rf_pwr_*`, `drive_permit_in`, `fast_permit_out`
The generator (D14) must reproduce all of them. `soft_drive_enable` is renamed by D11 (R5).

Issues seen in the ALSU delta, to fix while merging:

| # | Issue |
|---|---|
| A1 | `arc_inlk`: `reset_test_mask_r` is a hard-coded 4 bits and `{dev_reset_out, dev_test_out}` assumes `N_CH=3`. Size it as `N_CH+1`. |
| A2 | `arc_inlk`: `F_CLK` defaults to 125 MHz, and the shell does not pass it. ALSU's 114.7 MHz DSP clock gives a 0.545 s pulse. Derive it from `DSP_FREQ_MHZ` (already in `settings.mk`/`SYNTH_OPT`). |
| A3 | `arc_inlk`: test/reset requests that arrive during an active 0.5 s pulse are silently dropped. Add an `arc_testing` status bit so software can tell. |
`phase_ramp` stays as-is (D19). Only PR1 (needed by the toolchain) and PR2 (no behavior change at ALSU's clock) are applied now. PR3–PR5 are recorded for the future generic modulator (§1.2.1).

| PR1 | `phase_ramp` (**apply**): `dwell` uses `in_range` and `dwell_timeout` before they are declared. Verilator and sv2v are stricter about this; reorder the declarations. |
| PR2 | `phase_ramp` (**apply**): `timeout_counter` hard-codes `CLOCK_PERIOD = 8.7206e-9` (ALSU). Parameterize it from `DSP_FREQ_MHZ`; the ALSU value is unchanged. Keep the 10 s timeout. Done in step 3 as a `phase_ramp` `CLOCK_PERIOD` parameter with that default; ALSU's `DSP_FREQ_MHZ` (114.58) gives 8.7276e-9, so passing `1/F_DSP_HZ` in step 7 makes the timeout 0.08% longer. |
| PR3 | `phase_ramp` (*future*): `steps = 0` makes `steps-1` underflow, so the ramp never finishes and always times out. `step_cnt` and `timeout_en` are not cleared by `reset_all`. |
| PR4 | `phase_ramp` (*future*): it outputs an **absolute** setpoint latched from `setpoint_start`, so `phs_setpoint` writes are ignored while it holds, and opening the loop snaps back. ALSU keeps this behavior (D19). A generic modulator would use an offset accumulator. |
| PR5 | `phase_ramp` (*future*): the comment says the in-range filter is 3 cycles, but the code uses 8. Make it a parameter. Move `timeout_counter`/`programmable_timeout` into their own file. |
| S1 | SoC: `rs485_uart` and its pins are hard-wired in the shared `system.v`, and the Modbus sources and 64K BRAM are unconditional in `common.mk`. Every design would inherit them. |
| S2 | Naming trap: `system`'s port `PMOD2` is board `ZEST_PMOD1`, not board `PMOD2`. Name the expansion port by function (`rs485_*`), not by PMOD. |
| A4 | Main loop (kept as is in step 3): `update_in_progress` is set and never cleared, so after the first second the BSP status is refreshed on every loop iteration instead of at 1 Hz. |
| X1 | bedrock `xadc_pack.v` started a second DRP read after every XADC read; its DRDY OR-ed data into the next bus transaction (a corrupted instruction fetch in `soc/common/sim`). Fixed in bedrock 11af4fd (step 3). |
| Z1 | LEMP startup (pre-existing, seen in the step-3 `lemp_run`; not caused by step 3): after a bitstream load, BUFR `CLR` retries in bedrock `zest.c` `align_adc_clk_phase()` sometimes reach only two adjacent `clk_div` phases (ADC0 −43/−107, ADC1 −58/−122) and never the `phs_center` state (ADC0 ≈85, ADC1 ≈70), so the phase check fails after 128 retries. Which states are reachable is set per boot by the clock/ADC init (a soft reboot recovers; the same bitstream passes on other loads). The `clk_div`→`dsp_clk` crossing is a single `reg_tech_cdc` flop in an asynchronous clock group, so `phs_center` is its only margin control. Fix later in bedrock: re-run the clock/ADC init when the retries fail, and validate any extra accepted phase with long PN9 captures (and a phase sweep if available). |

### 0.4 Current status (step-1 baseline, 2026-10-06)

Reference results that later steps must reproduce (step 1, R2, R6). The reports themselves are kept outside the repository.

- Vivado: 2022.1, `xc7k160tffg676-2`, CI job `llrf_synthesis` (`top/marble_zest`, `make DESIGN=<d>`) on `main` 20c4c1c (bedrock b4ea165), on `alsu_fork` bb162b7 (bedrock e1313d5), and on the `LEMP` branch 2e25cd9 (bedrock 235f3e3; the later commits up to `origin/LEMP` 7e56f3b change only Python plotting scripts).
- CDC and tb: run locally on `main` 20c4c1c with bedrock e1313d5, on `alsu_fork` bb162b7, and on `LEMP` 2e25cd9 (`llrf_dsp/`, `llrf_dsp/tests/llrf_shell`). bedrock e1313d5 changes only `cic_wave_recorder`; with it, every newad `llrf_shell.json` and config-ROM JSON is byte-identical.
- `lemp` on `main` is a symlink to the uspas shell, not the LEMP-branch shell. The **LEMP-branch** row is the reference for step 9 (R1, R6), and `designs/lemp/_baseline/llrf_shell.json` is the LEMP-branch register map (2e25cd9).
- pip-ii is not in the CI synthesis matrix, so it has no Vivado result.

**Utilization and timing** (device totals: 101400 LUT, 202800 FF, 325 BRAM tiles, 600 DSP, 400 IOB)

| Design | Source | Slice LUT | Slice FF | BRAM tile | DSP | Bonded IOB | WNS / TNS (ns) | WHS / THS (ns) | WPWS (ns) |
|---|---|---|---|---|---|---|---|---|---|
| uspas | `main` | 23295 (22.97%) | 27219 (13.42%) | 232 (71.4%) | 32 (5.3%) | 148 | 0.554 / 0 | 0.047 / 0 | 0.264 |
| alsu | `main` | 23299 (22.98%) | 27223 (13.42%) | 232 (71.4%) | 32 (5.3%) | 148 | 0.200 / 0 | 0.041 / 0 | 0.264 |
| alsu | `alsu_fork` | 23661 (23.33%) | 27588 (13.60%) | 240.5 (74.0%) | 32 (5.3%) | 145 | 0.516 / 0 | 0.028 / 0 | 0.264 |
| lemp | `main` | 23298 (22.98%) | 27219 (13.42%) | 232 (71.4%) | 32 (5.3%) | 148 | 0.361 / 0 | 0.056 / 0 | 0.264 |
| lemp | `LEMP` branch | 25910 (25.55%) | 29990 (14.79%) | 136.5 (42.0%) | 34 (5.7%) | 144 | 0.375 / 0 | 0.041 / 0 | 0.264 |
| awa | `main` | 23455 (23.13%) | 27208 (13.42%) | 166 (51.1%) | 32 (5.3%) | 148 | 0.646 / 0 | 0.048 / 0 | 0.264 |
| pip-ii | `main` | — | — | — | — | — | — | — | — |

**Checks**

| Design | Source | Routing errors | DRC (all warnings) | CDC: CDC / OKX / BAD | tb `llrf_shell` (Verilator) |
|---|---|---|---|---|---|
| uspas | `main` | 0 | 23: LVDS-1 ×1, RPBF-3 ×22 | 278 / 646 / **0** | 12/12 |
| alsu | `main` | 0 | 23: LVDS-1 ×1, RPBF-3 ×22 | 278 / 646 / **0** | 8/8 |
| alsu | `alsu_fork` | 0 | 28: LVDS-1 ×1, RPBF-3 ×27 | 278 / 646 / **0** | 8/8 |
| lemp | `main` | 0 | 23: LVDS-1 ×1, RPBF-3 ×22 | 278 / 646 / **0** | 6/6 |
| lemp | `LEMP` branch | 0 | 28: PDRC-153 ×4, PLHOLDVIO-2 ×4, RPBF-3 ×20 | 300 / 451 / **0** | 60/60 (USPAS, ALSU, LEMP, AWA configs × 15) |
| awa | `main` | 0 | 23: LVDS-1 ×1, RPBF-3 ×22 | 278 / 646 / **0** | 12/12 |
| pip-ii | `main` | — | — | 278 / 646 / **0** | 12/12 |

Notes:
- Every build meets timing. ALSU on `main` has the smallest setup margin (WNS 0.200 ns); on `alsu_fork` it is 0.516 ns.
- `alsu_fork` costs +362 LUT, +365 FF and +8.5 BRAM tiles (+8 RAMB36, +1 RAMB18) over ALSU on `main`. The +8 RAMB36 is consistent with the SoC block RAM going from 32K to 64K (D22). The LUT/FF split between `phase_ramp`, the upgraded `arc_inlk` and the Modbus UART was not measured.
- Pin assignments (site, signal, IO standard, drive, slew) are identical on `main` and `alsu_fork`. `alsu_fork` drives the PMOD lines in a fixed direction (ARC detectors, FO board; IBUF 57→43, OBUF 27→38, OBUFT 15→7), so bonded IOBs drop from 148 to 145 and RPBF-3 (incomplete inout buffering) rises from 22 to 27.
- LVDS-1 is the bidirectional `ZEST_HDMI_D1/D2` LVDS pairs, present in every `main` and `alsu_fork` build. The LEMP branch drives HDMI through `OBUFDS` (19 vs 15), so LVDS-1 does not appear.
- LEMP branch vs ALSU/uspas on `main`: +2.6K LUT and +2.8K FF (interlock, triggers, local timing, fiber), 95.5 fewer BRAM tiles (`SIG_BUF_AW=10` vs 12), +2 DSP. Clocking and GT use are the same (1 GTX channel, 2 MMCM, 7 BUFG).
- LEMP-branch PDRC-153/PLHOLDVIO-2: the four event outputs of `timing_evr` (`i_ev1..4/flagtoggle_cdc`, also driven to `PMOD2[7:4]`) are LUT outputs that clock the four `freq_gcount` gray counters. Gated clocks; revisit when `timing_core_local` moves into `designs/lemp/` (step 9).
- The LEMP-branch tb must import the branch's own `uspas_llrf` (`PYTHONPATH=<LEMP checkout>`). With the `main` package it fails on `LLRFShell.DSP_CLK_CYCLE`.

---

## Part 1: Unify the variants

### 1.1 Address map

Shown for `SIG_BUF_AW=11` (all designs except LEMP):

```
0x00000-0x0ffff  status regs / config ROM compat         (window unchanged)
0x10800-0x10a2f  ready flags, slow bridge, mon/fault amp  (unchanged)
0x11000-0x11fff  rw scalar regs + mirror readback         (window unchanged, generated)
0x12000-0x15fff  adc0..7_buf                    8 x 2K
0x16000-0x1afff  adc0..7_i_buf, drv0..1_i_buf   10 x 2K
0x1b000-0x1ffff  adc0..7_q_buf, drv0..1_q_buf   10 x 2K
0x20000-0x23fff  loop0_amp_lut                  16K x 18b
0x24000-0x27fff  loop0_phs_lut                  16K x 18b
0x28000-0x2bfff  loop1_amp_lut                  16K x 18b
0x2c000-0x2ffff  loop1_phs_lut                  16K x 18b
0x30000-0x3ffff  circle buffer                            (unchanged)
```

- The amp LUT bases match pip-ii's `pulse0/1_lut`. Depth goes from 32K to 16K, and `pulse_res_shift` stretches the LUT to longer pulses.
- BRAM cost stays at about 32 RAMB36 (4 × 16K×18, using the native 2K×18 BRAM width). That equals pip-ii's 2 × 32K×16 today.
- 18-bit entries give full `DWBB` resolution for both amplitude and phase.
- `SIG_BUF_AW=11` halves signal-buffer BRAM for uspas and alsu.
- Signal buffers are packed at their natural size, `2^SIG_BUF_AW`, in a fixed order: raw ADC, then I (adc0..7, drv0..1), then Q. The 20 I/Q buffers are therefore one contiguous region in every design. The LUT and circle-buffer bases are fixed for all designs; the buffer bases depend on `SIG_BUF_AW` (D5).
- LEMP (`SIG_BUF_AW=10`, D1) packs to:

  ```
  0x12000-0x13fff  adc0..7_buf                    8 x 1K
  0x14000-0x167ff  adc0..7_i_buf, drv0..1_i_buf   10 x 1K
  0x16800-0x18fff  adc0..7_q_buf, drv0..1_q_buf   10 x 1K
  0x14000-0x1bfff  iq_buf (alias)                 addr_width 15: all 20 I/Q buffers in one read
  0x19000-0x1ffff  unused
  0x20000-...      LUTs and circle buffer, as above
  ```

  `iq_buf` keeps LEMP's one-call waveform readout with `addr_width` 15, as on the LEMP branch (base `0x1c000` there). With 2K slots it would need 16 and read twice the data. The alias is only a JSON entry over the per-buffer decodes; its unused tail (`0x19000`–`0x1bfff`) reads as an unmapped address.

### 1.2 Pulse modulation (amplitude + phase LUT) in `loop_ctrl`

Per loop:

```
pulse_gen (single counter, extended)  -> pulse_dval, idx = (pc - start) >> res   (P3, P5)
dpram #(.aw(14), .dw(18)) amp_lut     port A: lb_clk r/w, port B: dsp_clk read
dpram #(.aw(14), .dw(18)) phs_lut
amp_sp = sat(amp_setpoint + (mod_en[0] & dval_d2 ? amp_lut : 0))  -> existing open-loop max clamp
phs_sp =     phs_setpoint + (mod_en[1] & dval_d2 ? phs_lut : 0) + phs_offset
             (phase wraps, no sat; phs_offset is a design hook, tied to 0 in the base shell)
```

The `phs_offset` hook is used by two design shells:
- **LEMP:** phase step from `pulse_idx`.
- **ALSU:** `phase_ramp` on loop 0, with `phs_offset = setpoint_finish - loop0_phs_setpoint`. The effective setpoint is then exactly `phase_ramp`'s absolute output, so today's behavior is reproduced bit for bit (D19).

Registers per loop:
- `loopN_lut_len`, 15 bits, saturated to 2^14
- `loopN_mod_enable[1:0]` (bit0 amp LUT, bit1 phase LUT)
- `loopN_pulse_res_shift`

These replace pip-ii's `lut0_len`, `lut1_len`, `pulse_modulation_enable` and the shared `pulse_res_shift`. LEMP's `loopN_phs_shift` and `loopN_phs_shift_delay` are kept (D9). `loop_ctrl` exports `pulse_idx`/`pulse_dval` and takes an additive `phs_offset` input; the LEMP shell computes the phase step from them (fixes L5).

Fixes for the review findings on [pip-ii/llrf_shell.v](../designs/pip-ii/llrf_shell.v):

| # | Fix |
|---|---|
| P1 | Remove the dead `drive_i_mod`/`drive_q_mod` code ([:839](../designs/pip-ii/llrf_shell.v#L839)). `res` means time resolution only. |
| P2 | Saturate `lut_len` to `1<<LUT_AW` ([:1217](../designs/pip-ii/llrf_shell.v#L1217) truncates). |
| P3 | Index from the pulse start, `(pc - start) >> res` ([:1191](../designs/pip-ii/llrf_shell.v#L1191) indexes from the trigger). |
| P4 | Align the gate with LUT data. `dpram` adds 1 clock and the index register adds 1, so the `dval` gate is delayed by 2 clocks (`dval_d2`) ([:745](../designs/pip-ii/llrf_shell.v#L745)). |
| P5 | Extend `llrf_dsp/pulse_gen.v` with an index output. Delete `mod_pulse_gen` and `pulse_lut_ram`. |
| P6 | Widen `end_val` to AW+1 bits in `pulse_gen.v`, so `start + high_len` cannot wrap. Use AW=32 everywhere (LEMP needs it). |
| P7 | Make `res` per loop. Leave modulation independent of `drvN_pulse_mode` and document it. |
| P8 | Add `test_pulse_modulation` and a bit-accurate model (§2.5). |
| P9 | `phase_ramp`: apply PR1–PR2 only (D19); add ALSU `test_phase_ramp`, ported from `phase_ramp_tb.v`. |

#### 1.2.1 Future: generic loop modulator (not scheduled)

Once `loop_ctrl` is stable, consider adding a **function-generator source** next to the LUT AWG: an error-gated staircase or ramp, the same idea as `phase_ramp`. It would generalize ALSU's ramp to any loop and to amplitude or phase.

| Source | Shape | Timing | Gating | Today |
|---|---|---|---|---|
| LUT (AWG) | arbitrary, amp + phase | from pulse start, `2^res` clocks per entry | `pulse_dval` | in `loop_ctrl` (all designs) |
| Function generator | staircase `steps` × `rate` | `ramp_start` edge (EVR/soft/`wave_trig`), dwell `ttime` | \|err\| < threshold, timeout | ALSU-only `phase_ramp` via `phs_offset` |

A generic version would address PR3–PR5: an offset accumulator, a strobe-based clear, `steps=0` handling, a parameterized filter, and per-loop instances using the `loopN_<func>_*` names. ALSU would move to it only after an explicit decision and a hardware comparison against its `phase_ramp`.

### 1.3 Behavioral impact accepted

- **uspas, alsu:** 2K buffers; all buffer addresses move.
- **awa:** zero-valued `dac_raw_out` dropped; IQ buffers move.
- **pip-ii:** IQ buffers unchanged. LUTs are renamed and become 16K deep, and each loop gains a phase LUT.
- **LEMP:** keeps 1K buffers and the `iq_buf` window (`addr_width` 15) (D1); buffer addresses move to the packed layout in §1.1. Phase-step registers are unchanged, and the LUTs are added.
- **ALSU:** gets its own thin shell (from step 7) so it can wire `phase_ramp` on loop 0. Gains the LUTs; the arc test/reset strobes are already on `alsu_fork`. `phase_ramp_*` registers are renamed `loop0_phs_ramp_*` (D21). Modbus map names are preserved.
- **All designs (D18):** `arc_test_arc_dev` (level) → `arc_test_mask` + `arc_test_stb`, and `arc_reset_arc_dev` becomes a strobe with a 0.5 s output pulse.
- **All non-LEMP designs:** `pulse_modes` → `drv0/1_pulse_mode` and `soft_drive_enable` → `soft_drive0/1_enable` (D11). leep names, init JSON and model fields change with them.

---

## Part 2: SystemVerilog architecture: shared blocks, per-design shells

### 2.1 Layering

```
llrf_dsp/                         shared, tested blocks (one copy)
  llrf_shell_pkg.sv               types, constants, addr helpers
  rx_chain.sv  loop_ctrl.sv  tx_chain.sv  diag.sv  lb_rd_mux.sv
  lb_xdomain.sv (lb1/lb2/lb3)     pulse_gen.v  dsp_core.v  cic_waves.v  ...
designs/<d>/                      per-design customization
  llrf_shell.sv                   thin assembly: ports, regs instance, permits, timing, extras
  design.py                       register/block/feature declaration (extends base)
  _gen/                           generated: llrf_shell_regs.sv, regmap pkg, llrf_shell.json
  tb/llrf_shell/                  TB_llrf_shell subclass for design-specific tests
designs/lemp/                    + timing_core_local.v  fiducial_int_gen.v  triggers.v  interlock/
designs/alsu/                    + llrf_shell.sv (thin: base blocks + phase_ramp on loop0)  phase_ramp.v  scripts/
  tb/fiducial_int_gen/           unit test moved from LEMP's llrf_dsp/tests/ (D12)
```

The top level and the SoC follow the same base-plus-override pattern: `top/common/` + `top/<design>/` (§2.8) and `soc/common/` + `soc/<design>/` (§2.9).

`designs/rules.mk` gains a `DESIGN_SRC` list, so a design can add its own modules to the expansion and CDC sources.

- **Base shell:** `designs/uspas/llrf_shell.sv` is the reference assembly. awa and pip-ii **reuse it unchanged** (alsu does too until step 7): each Makefile sets `SHELL_SRC = ../uspas/llrf_shell.sv` instead of using a symlink, and differs only by `FSET`/parameters.
- **Custom shells:**
  - `designs/lemp/llrf_shell.sv` instantiates the same blocks with LEMP parameters, then adds its own ports, interlock, timing and triggers.
  - `designs/alsu/llrf_shell.sv` is the base assembly plus `phase_ramp`: `ramp_start` = EVR event, `error` = `loop_ctrl[0].err_phs`, output into `phs_offset[0]`.
- **Customization rules:** only through
  1. block parameters
  2. what the design shell wires around the blocks: permits, triggers, I/O and extra readback
  3. extra regmap windows declared in `design.py`

  Design shells never fork a block. A feature two designs need is promoted into a block parameter.

### 2.2 Block contracts

| Block | Ports (SV) | Parameters for variation |
|---|---|---|
| `rx_chain` | `adc_t adc[N_ADC]`, LO, `i_sel` → `iq_t sig_iq[N_ADC]` (to loops), `iq_t sig_iq_mon[N_ADC]` (to diag) | `DC_CH_MASK` (LEMP `8'b1100_0000`): those channels bypass the DDC on the monitor path (I=ADC≪guard, Q=0, fixes L1), while the loop path stays DDC |
| `loop_ctrl` | `loop_cfg_t cfg`, `iq_t field`, `trig`, `drive_permit`, `phs_offset`, `lb_if.slave` (2 LUT windows) → `iq_t drive`, `pulse_dval`, `pulse_idx`, `err` (amp/phs, for design hooks such as ALSU `phase_ramp`) | `LUT_AW` (14), `PULSE_AW` (32); generate × `N_DRIVE` |
| `tx_chain` | `iq_t drive[N_DRIVE]`, `dac_drive_sel`, flip → `dac_a/b` | — |
| `diag` | `iq_t sig[N_CH]`, raw `adc[N_ADC]`, `buf_trig`, `cbuf_trig` → sig_buf array, cic_waves, monitor_inlk, arc_inlk (D18: test/reset strobes, 0.5 s pulse), `lb_if.slave` windows, `inlk_permit`; ARC detector IO passed to the shell | `SIG_BUF_AW` (11; LEMP 10, D1), `CBUF_AW`, `F_CLK` (from `DSP_FREQ_MHZ`, A2) |
| `lb_rd_mux` | `{hit[i], rdata[i]}` × N_WIN → `lb_rdata` | registered, READ_DELAY=3 preserved |
| design shell | flat Verilog-compatible ports, `llrf_shell_regs` instance (cfg/status structs), permits, trigger source, timing, design status wiring | — |

The permit logic stays in the design shell. uspas/alsu use `drive_permit_in`/`slow_permit_in`/arc; LEMP uses `intlk_latch_in` plus fiducial re-arm. Each shell hands `loop_ctrl` one `drive_permit[N_DRIVE]` vector.

Trigger selection is also design-owned, but uses one shared `WAVE_TRIG_*` encoding from the package, with `FIDUCIAL` added (L4). `buf_delay` becomes a generic `diag` input; uspas ties it to 0 or a register.

### 2.3 Package and types: `llrf_dsp/llrf_shell_pkg.sv`

```systemverilog
package llrf_shell_pkg;
  localparam int N_ADC = 8, N_DRIVE = 2, N_CH = N_ADC + N_DRIVE;
  localparam int DW = 16, DWLO = 18, DWBB = 18, LB_ADW = 18;
  typedef logic        [LB_ADW-1:0] addr_t;
  typedef logic signed [DW-1:0]     adc_t;
  typedef logic signed [DWBB-1:0]   bb_t;
  typedef struct packed { bb_t i; bb_t q; } iq_t;
  typedef struct packed {
    bb_t amp_setpoint, max_amp_setpoint, phs_setpoint, kp_amp, ki_amp, kp_phs, ki_phs;
    logic amp_enable, phs_enable, amp_reset, phs_reset, pulse_mode;
    logic [31:0] pulse_start, pulse_high_len;
    logic [14:0] lut_len;  logic [3:0] res_shift;  logic [1:0] mod_enable;
  } loop_cfg_t;
  typedef enum logic [2:0] { WT_INT=0, WT_EXT=1, WT_SOFT=2, WT_EVR=3,
                             WT_ALWAYS=4, WT_MIXED=5, WT_FIDUCIAL=6 } wave_trig_sel_t;
  function automatic logic addr_in_array(addr_t a, addr_t base, int aw);
    return (a >= base) && (a < base + (addr_t'(1) << aw));
  endfunction
endpackage
```

### 2.4 Register map and register-file generation (D4, D14: replaces newad)

newad is retired for `llrf_shell`. `marble_bsp` keeps it; that is out of scope. One Python declaration produces everything newad and the hand-written `static_regmap.json` produce today.

**What newad does for the shell today, and what replaces it:**

| newad function | Replacement |
|---|---|
| `// reg ... top-level` comments → register storage and `` `AUTOMATIC_decode `` | Generated `llrf_shell_regs.sv`: one decode per clock domain. Outputs are packed structs `cfg_lb_t`, `cfg_dsp_t`, `cfg_dac_t`, `cfg_evr_t` |
| `newad-force lb1/lb2/lb3 domain` (bus copied by `data_xdomain` into dsp/dac/gt clocks) | `domain=` attribute on each register. The generator emits the same `data_xdomain` bus copies (moved from the shell into `lb_xdomain.sv`), so CDC structure is unchanged |
| `single-cycle` strobes | `kind='strobe'` → 1-cycle pulse in the target domain |
| `-m` mirror readback window (`0x11000`, `mirror_out_0`) | Generated lb-domain shadow and readback mux for all rw registers |
| `regmap_*.json` + `scalar_*_regmap.json` + `merge_json.py` | Generator writes `llrf_shell.json` directly, in the **same leep schema** (`base_addr`, `addr_width`, `access`, `data_width`, `sign`, `description`) |
| `// auto(ix,N)` per-instance regs (LEMP `triggers`) | Array registers, `Reg('trigN_delay', count=4)` → `cfg.trig_delay[4]` |
| `` `AUTOMATIC_map ``, `_auto.vh`, `addr_map_*.vh` | Not needed. The shell instantiates `llrf_shell_regs` and reads struct fields |

**Declaration** (`uspas_llrf/regmap.py` holds the base; `designs/<d>/design.py` extends or overrides it):

```python
REGS = [
  Reg('rx_dds_phase_step', 32, domain='dsp'),
  Reg('wave_trig_sel', 3, domain='dsp', enum=WaveTrigSel),
  Reg('dac_drive_sel', 2, domain='dac', enum=DacDriveSel),
  Reg('evcode', 8, domain='evr'),
  Reg('circle_buf_flip', 1, kind='strobe', domain='lb'),
  *loop_regs(N_DRIVE),          # loopN_amp_setpoint ... loopN_lut_len, drvN_pulse_mode, soft_driveN_enable
]
STATUS = [                       # read-only, wired by the design shell into status_t
  Status('rf_pwr_hi', 10, domain='lb'),
  Status('loop0_amp_err', 15, domain='dsp'),   # dsp-domain status -> jit_rad_gateway bank
]
BLOCKS = [*sig_bufs(SIG_BUF_AW), *mod_luts(LUT_AW), Block('circle_data', aw=CBUF_AW, dw=24)]
# designs/lemp/design.py adds: Alias('iq_buf', base='adc0_i_buf', aw=15)
```

**Outputs** (into `designs/<d>/_gen/`):
1. `llrf_shell_regs.sv`: storage, per-domain decode and crossings, strobes, mirror, status readback (lb and jit_rad banks)
2. `llrf_shell_regmap_pkg.sv`: `cfg_*_t`/`status_t` structs, `ADDR_*`/`AW_*`, and index-ordered arrays (`ADDR_SIG_I_BUF[N_CH]`, `ADDR_AMP_LUT[N_DRIVE]`) for generate loops
3. `llrf_shell.json`, consumed unchanged by `leep.build_rom` (config ROM), `soc/.../localbus_address_map.py` (C header), `gen_init_reg.py` and `LocalbusAppMaster`
4. a README address table

**Allocation:**
- Address windows stay where they are today: status `0x00000`–, rw scalars `0x11000`– (mirror), blocks `0x12000`–`0x3ffff`.
- Inside each window the allocator assigns addresses with natural alignment and an overlap check. Scalar addresses may move (D5).
- Signal buffers are packed at their natural size (`2^SIG_BUF_AW`) in the fixed order raw ADC, I, Q, so the I/Q buffers are contiguous (§1.1). LUTs and the circle buffer keep fixed bases.
- `Alias(name, base=<block>, aw=N)` adds a read window over a contiguous run of blocks (LEMP `iq_buf`). It goes into the JSON only, adds no decode, and is exempt from the overlap check as long as it covers only signal buffers and unused space.
- `design.py` blocks go into a reserved design window.

**Naming:** registers keep flat names (`loopN_*`, `drvN_pulse_mode`, `soft_driveN_enable`; D9, D11). A generated pack fills `loop_cfg_t cfg[N_DRIVE]`, replacing the ~30 hand-written `assign`s.

**Checks:**
- `test_regmap_consistency` (cic_waves pattern): `P_ADDR_*` exported by the shell must equal the JSON.
- `test_regmap_compat` compares each design's generated JSON with the **baseline newad JSON captured in step 1** (for LEMP, `designs/lemp/_baseline/llrf_shell.json` is the LEMP-branch JSON, see step 1). Names, `data_width`, `sign` and `access` must match, except the intentional renames (D11) and additions (LUTs) listed in an allow-list.
- Every `LLRFInitRegisters` field must exist in the regmap with a matching width.
- Every `leep_name` in `soc/alsu/mb_addr_map.toml` must exist in ALSU's generated JSON, including the instance-derived `arc_*`/`inlk_*` names and the `rf_pwr_*` aliases.

**Build** (`designs/rules.mk`, newad include removed):

```
regmap.py + design.py --> _gen/{llrf_shell_regs.sv, llrf_shell_regmap_pkg.sv, llrf_shell.json}
*.sv + *.v (blocks, design shell, _gen) --sv2v--> llrf_shell_expand.v   (single file, Verilog-2005)
```

`llrf_shell_expand.v` and `llrf_shell.json` remain the **only** artifacts that `top/marble_zest` and `soc/` consume, so the top-level integration contract is unchanged (see §2.8 for the per-design top).

#### 2.4.1 Register naming convention (D11, D21)

Every register is declared in `regmap.py`/`design.py`, so these rules are enforced in one place. The generator rejects names that break them.

| Scope | Pattern | Examples |
|---|---|---|
| Per loop (N = 0..N_DRIVE-1) | `loopN_<func>_<field>`, or `loopN_<field>` for core loop regs | `loop0_amp_setpoint`, `loop1_lut_len`, `loop0_phs_shift_delay`, `loop0_phs_ramp_rate` |
| Per drive output | `drvN_<field>`, `soft_driveN_<field>` | `drv0_pulse_mode`, `soft_drive1_enable` |
| Per block instance (was newad `// auto`) | `<inst>_<field>`, keeping today's names | `arc_test_mask`, `arc_reset_arc_dev`, `inlk_inlk_mode` |
| Arrays | base name; tools unroll to `<name>_<i>` (`localBusAddressMap.py`) | `mon_phs` → `MON_PHS_0` |
| Status aliases | kept as today | `rf_pwr_status`, `drive_permit_in` |

Renames (all in the step that introduces them; consumers updated in the same MR, R5):

| Old | New | Where |
|---|---|---|
| `pulse_modes[1:0]` | `drv0_pulse_mode`, `drv1_pulse_mode` | all designs (D11) |
| `soft_drive_enable[1:0]` | `soft_drive0_enable`, `soft_drive1_enable` | all designs, ALSU `mb_addr_map.toml` (D11) |
| `lut0_len`, `lut1_len`, `pulse_res_shift`, `pulse_modulation_enable` | `loopN_lut_len`, `loopN_pulse_res_shift`, `loopN_mod_enable` | pip-ii (§1.2) |
| `pulse0_lut`, `pulse1_lut` | `loopN_amp_lut` (+ new `loopN_phs_lut`) | pip-ii (§1.1) |
| `arc_test_arc_dev` | `arc_test_mask` + `arc_test_stb` | all designs (D18) |
| `phase_ramp_enable` | `loop0_phs_ramp_enable` | ALSU (D21) |
| `phase_ramp_steps` | `loop0_phs_ramp_steps` | ALSU |
| `phase_ramp_rate` | `loop0_phs_ramp_rate` | ALSU |
| `phase_ramp_ttime` | `loop0_phs_ramp_ttime` | ALSU |
| `phase_ramp_error_threshold` | `loop0_phs_ramp_error_threshold` | ALSU |
| status `ramp_finish`, `ramping_i`, `timeout_i` | `loop0_phs_ramp_finish`, `loop0_phs_ramp_ramping`, `loop0_phs_ramp_timeout` | ALSU |

`test_regmap_compat` reads this rename table as its allow-list.

### 2.5 Model integration (`uspas_llrf/model/llrf_shell.py`)

1. **Design-aware model.** `LLRFShell(dsp_config, design='lemp')` loads features from `designs/<d>/design.py` or `uspas_llrf.regmap`: `sig_buf_aw`, `dc_ch_mask`, extra blocks. No hard-coded geometry.
2. **Init registers.** Add `loopN_lut_len`, `loopN_mod_enable` and `loopN_pulse_res_shift` (default 0, so CW behavior is unchanged). Add `buf_delay`. Rename `pulse_modes` → `drv0/1_pulse_mode` and `soft_drive_enable` → `soft_drive0/1_enable` (D11), and update `settings.json` `PULSE_MODES` consumers. A LEMP subclass adds `loopN_phs_shift`, `loopN_phs_shift_delay`, `fiducial_sel`, `event_sel` and the trigger regs. Regenerate `llrf_shell_init_regs.json` per design.
3. **Bit-accurate `PulseModulator`.** Mirrors the extended `pulse_gen` index, the 2-clock latency, additive saturated amplitude, wrapped phase plus optional `phs_offset` step (LEMP), and the open-loop clamp. It is the cocotb scoreboard.
4. **LUT helpers.** `gen_pulse_lut(kind, ...)` returns `(amp_lut, phs_lut)` as int18 arrays in setpoint units, clipped against `cal_factors.max_amp_setpoint`.
5. **DC channels.** `RX` gains a `dc_coupled` flag (gain = `2**(DWBB-DW)`, no LO), so `cic_wfm_gain`/`rx_iq_gain` are right for LEMP ch 6–7.
6. **`PhaseRamp` model (ALSU).** Bit-accurate copy of today's `phase_ramp`: in-range filter, dwell, step count, timeout, absolute setpoint. It lives with the ALSU model extension and is the scoreboard for ALSU's `test_phase_ramp`.
7. **One trigger enum.** `WaveTrigSel` imports the package encoding, generated from `regmap.py` or parsed, so Python and RTL share it (L4).

### 2.6 Testbench structure

- `TB_llrf_shell` (base) gets feature-driven tests. Run in **every** design:
  - `test_pulse_modulation`: amp and phase; corner cases `lut_len ∈ {0, 1, 2^14}`, `res > 0`, saturation, phase wrap, `start > 0`
  - `test_arc_inlk`: test/reset strobes, 0.5 s pulse (`F_CLK` scaled down in sim), requests dropped while busy, `arc_testing` status
  - `test_regmap_consistency`
- `designs/lemp/tb/llrf_shell/test_llrf_shell.py` subclasses it and adds:
  - DC-channel capture
  - interlock-latch / fiducial re-arm
  - `fiducial_int_gen` trigger
  - pmod triggers
- `designs/alsu/tb/llrf_shell/test_llrf_shell.py` subclasses the base TB (from step 7) and adds `test_phase_ramp`. It runs closed loop with the EVR event as start; the ramp advances only while the error is in range; covers timeout and loop-open snap-back. Modbus is tested on hardware (`designs/alsu/scripts/modbus_test.py`, `alsu_run` CI).
- Unit tests for each block in `llrf_dsp/tests/{rx_chain,loop_ctrl,tx_chain,diag}`, following the cic_waves SV-wrapper pattern.

### 2.7 Toolchain impact

| Tool | Status | Action |
|---|---|---|
| Verilator 5.051 | OK | Primary simulator for SV blocks and shells |
| Vivado 2022.1+ | OK | none |
| Icarus 12 | no interfaces | Optional: can run on the sv2v output |
| sv2v v0.0.13 (installed) | — | Produces `llrf_shell_expand.v`. Pin the version in `doc/developer_guide.md` and CI |
| Yosys 0.52 CDC check | limited `-sv` | Reads the sv2v output (`llrf_shell_skin.v` + `llrf_shell_expand.v`), unchanged rule |
| newad | — | Retired for `llrf_shell` (D14). Remove `newad_top_rules.mk` from `designs/rules.mk` |
| `top/marble_zest` | one dir for all designs, shared `_xilinx/` | Split into `top/common/` + `top/<design>/` (§2.8) |

### 2.8 Per-design top level: `top/<design>/` (D16)

**Why.** `top/marble_zest/` builds every design from one directory with `make DESIGN=x`. The design-specific top-level changes LEMP needs, and that today exist only on its branch, are:
- a separate **`interlock_wrapper` IP** on localbus segment 2 (`lb_addr[21:18]==2`), with its own `interlock_wrapper.json` merged into the config ROM
- **HDMI pins** changed from `inout` to `output`, driven by `OBUFDS` (modulator/SSSB/scope triggers gated by `mod_permit_out`)
- **PMODs** taken from `marble_bsp` and given to `pmod_trigs`, with different pull settings
- new `llrf_shell` ports (`intlk_latch`, `dds_*`, `sssb_*`, `evr_events`, `fiducial_ext`)
- a **fiber/GTP link** (`fiber_top.v`, `gtp_config/*.tcl`, `fiber_rules.mk`), extra XDC (QSFP2 pins, false paths) and `flash.sh`

On top of that, all designs share one `_xilinx/` project directory, so they cannot be built in parallel; the Makefile has a TODO for this.

**Layout** (mirrors `designs/`: a shared base, thin per-design directories, overrides only where needed):

```
top/common/                       board-level base for Marble + Zest (moved from top/marble_zest/)
  top_rules.mk                    IP_EXPAND/IP_JSON assembly, config_romx, gitid, bitstream, system_config/test
  marble_zest_top.v               base top: fixed board ports + `include "design_io.vh"
  marble_zest_mid.vh              system + config ROM + llrf_shell + marble_bsp, lb segments 0/1,
                                  + `include "design_mid.vh" for segments >= 2
  marble_zest_frame.v, topsim.*   simulation frame (Verilator top sim)
  pin_map.csv, timing.xdc         base constraints
  design_io.vh, design_mid.vh     empty defaults
top/<design>/                     one per design: uspas, alsu, lemp, awa, pip-ii
  Makefile                        DESIGN=<d>; include ../common/top_rules.mk; optional overrides
  design_io.vh   (optional)       extra top ports and IO buffers (LEMP: HDMI OBUFDS, PMOD, SSSB, fiber)
  design_mid.vh  (optional)       extra IP instances + lb segments (LEMP: interlock_wrapper @ seg 2)
  design.xdc     (optional)       extra or overriding constraints (LEMP: QSFP2 pins, PMOD pulls, false paths)
  *.v / *.tcl    (optional)       design-only sources (LEMP: fiber_top.v, gtp_config/)
  _xilinx/                        per-design Vivado project (enables parallel builds)
```

ALSU's top differences, already on `alsu_fork` (§0.3), go into `top/alsu/design_mid.vh`:
- PMOD1 → ARC detectors (`arc_permit_in`, `arc_test_out`, `arc_reset_out`)
- PMOD2 → FO board permits
- `rs485_uart` on the SoC expansion port, with pins on `ZEST_PMOD1[3:0]` (§2.9)

The base `marble_zest_mid.vh` wires PMOD1/PMOD2 to `system` only when the design does not claim them (`` `ifndef DESIGN_OWNS_PMOD1 ``, added with ALSU in step 3).

**Override hooks** in `top/common/top_rules.mk` (defaults keep today's behavior):

| Variable | Default | LEMP example |
|---|---|---|
| `IP_EXPAND +=` | system, marble_bsp, `designs/<d>/llrf_shell_expand.v` | `+= designs/lemp/interlock/interlock_wrapper_expand.v` |
| `IP_JSON +=` | llrf_shell, marble_bsp, top | `+= .../interlock_wrapper.json` (with segment-2 base) |
| `TOP_SRC +=` | — | `fiber_top.v` + bedrock `mgt/qgtp_*` |
| `XDC_FILES +=` | `top.xdc`, `timing.xdc` | `design.xdc` |
| `TCL_HOOKS +=` | evr GT TCL | `gtp_setup.tcl` |
| `SOC_DESIGN` | `<d>` | builds `soc/<d>/` firmware and features (§2.9) |
| `PIN_MAP` | `../common/pin_map.csv` | own copy only if a base pin changes; prefer `design.xdc` overrides |

**Rules:**
- Board ports are fixed in the base top. Only ports the base leaves unused (HDMI, PMOD, QSFP2) can be claimed through `design_io.vh`.
- A port whose direction changes, such as HDMI `inout` → `output`, gets a `` `ifdef DESIGN_IO_<PORT> `` guard in the base declaration, so the design include can redeclare it without forking `marble_zest_top.v`.
- Localbus segments 0 (`llrf_shell`) and 1 (`marble_bsp`) are fixed. Segments 2 and up belong to the design. The `lb_rdata` mux gets a design extension with the first design that needs one (LEMP, step 9); `design_mid.vh` is included after the mux, so a plain macro there would be too late.
- Design-only IP lives under the design. LEMP's `interlock/` moves to `designs/lemp/interlock/`. It may keep newad, since D14 covers only `llrf_shell`. Its duplicate `ddc.v`, `noniq_ddc.v` and `triggers.v` are de-duplicated against `llrf_dsp/` and `designs/lemp/`.
- Entry points become `make -C top/<design>`, `make -C top/<design> system_config MARBLE_SERIAL=61`, and `make -C top/<design> system_test`. `top/marble_zest/Makefile` stays for one release as a forwarder, `make DESIGN=x` → `make -C ../x`. The SoC build (`soc/marble_zest/synth`) keeps taking `DESIGN`.

**Verification:**
- For each existing design, the per-design build must reproduce the step-1 baseline: same Vivado utilization and timing, same config ROM JSON, and `topsim` passing.
- Step 2 result: every Vivado input is byte-identical to the old layout for all five designs (`config_romx.v`, `llrf_shell_expand.v`, `system_expand.v`, `system_top.xdc`, `system32.dat`, tclargs), and the preprocessed `marble_zest_top.v` is identical; the only differences are the empty `design_io.vh`/`design_mid.vh` includes and absolute paths in comments of `marble_bsp_expand.v`. `soc/common/sim` passes.
- `topsim` was already broken before step 2 (it predates the `designs/` split: `llrf_shell`, `xadc_pack` and the GT primitives are not found). Fixing it is a separate item.
- For LEMP, compare `top/lemp` against the LEMP branch's `top/marble_zest` build: same utilization ballpark, identical pin and IO-standard report (`report_io`), and identical localbus segment map. ⚠ R1, R6

### 2.9 Per-design SoC: `soc/common/` + `soc/<design>/` (D20)

**Why.** `soc/marble_zest/` is shared by every design. Per-design differences are already handled by file-name suffixes (`init_zest_$(FSET).c`, `init_marble_$(FSET).c`). ALSU now needs extra hardware (Modbus UART1), extra firmware, a different `BLOCK_RAM_SIZE` and settings (`ZEST_BYPASS_AD7794_READS`), none of which other designs should inherit (S1).

**Layout** (parallel to `designs/` and `top/`):

```
soc/common/                       shared PicoRV32 SoC (moved from soc/marble_zest/common/)
  common.mk                       base SRC_V/SRCS, BLOCK_RAM_SIZE ?= 32768, includes soc/<design>/design.mk
  system.v                        base SoC + expansion port (below)
  system.c, console.c, settings.h shared firmware; settings.h includes "settings_design.h"
  llrf/                           llrf.c, gen_init_reg.py, localBusAddressMap.py (shared fixes from ALSU)
  sim/, top_sim/                  simulation, parameterized by DESIGN
  synth/                          standalone SoC bitstream (system_top.v)
soc/<design>/                     one per design: uspas, alsu, lemp, awa, pip-ii
  design.mk                       SOC feature flags, extra SRCS/SRC_V, BLOCK_RAM_SIZE override
  settings_design.h               design #defines (empty by default)
  init_zest.c, init_marble.c      moved from common/init_*_<FSET>.c (pip-ii reuses soc/awa/ ones)
  (alsu) init_modbus.c/.h, mb_addr_map.toml, modbusAddrMap.py
```

**Hardware hook: SoC expansion port** (added in step 3 with ALSU, its first user, so step 2 stays a pure re-layout). `system.v` keeps the core peripherals and exports one generic port:
- `ext_mem_packed_fwd` (CPU → peripheral) and `ext_mem_packed_ret` (OR-ed into the return bus)
- `ext_irq[3:0]`, mapped to `irqFlags[7:4]`

Design peripherals are instantiated **outside** `system.v`, in `top/<design>/design_mid.vh` (§2.8), which also owns their pins. ALSU puts `rs485_uart #(.BASE_ADDR(8'h06))` there, with `ext_irq[0]` = UART1 RX and pins on `ZEST_PMOD1[3:0]`. That fixes S1 and S2, and `system.v` has no ALSU-specific code.

**Firmware hook** (`design.mk` and `settings_design.h` exist from step 2; the hooks below come with ALSU in step 3).
- `design.mk` is included at the end of `common.mk`, so it can extend `SRC_V`, `SRCS` and `CFLAGS` and set `BLOCK_RAM_SIZE`. ALSU adds `rs485_uart`, the Modbus client and its generated register map, and `BLOCK_RAM_SIZE=65536` (ALSU-only, D22; others keep the 32768 default).
- `system.c` calls `design_init()`, `design_irq(irqs)` and `design_poll()`, and `console.c` calls `design_console(c)`. Weak no-op defaults are in `soc/common/design_hooks.c`; ALSU defines them in `soc/alsu/alsu_hooks.c` (Modbus init, RX IRQ, poll, console `s`), so the common code has no `#ifdef` tangle.
- ALSU's main-loop timing change is the `DESIGN_FAST_MAIN_LOOP` define in `settings_design.h`. The other designs keep the 20 Hz loop.

**Build wiring.**
- `top/common/top_rules.mk` builds the firmware, `system_expand.v` and `zest_fmc_dp.xdc` with `make -C soc/<design>/build -f soc/common/synth/Makefile DESIGN=<d>`, so per-design images do not collide. Before step 2 they shared `soc/marble_zest/synth/` and were only rebuilt when missing, so a local build of a second design reused the first design's firmware.
- `designs/<d>/llrf_shell_init_regs.json` (input to `init_llrf.c`) has a rule with no prerequisites, so a stale copy is never regenerated after model changes. Add the model as a prerequisite (separate fix).
- `mb_addr_map.toml` is validated against the generated `llrf_shell.json`: every `leep_name` must exist (§2.4 checks).

**Verification:**
- Each non-ALSU design's `system32.dat` stays functionally unchanged (same `system.map` symbols, same BRAM size), and `soc/common/sim` passes.
- ALSU must match the `alsu_fork` build: Modbus registers respond (`designs/alsu/scripts/modbus_test.py` on hardware), and `report_io` shows RS485 on the same pins. ⚠ R7

---

## 3. Branch merge-back

### 3.1 LEMP (`origin/LEMP`)

LEMP diverged before the `designs/` split and carries about 2800 lines of app and analysis scripts, so a direct `git merge` of `llrf_dsp/llrf_shell.v` would conflict everywhere. Instead:

1. **Bring LEMP pieces to main, with tests.**
   - LEMP-only, into `designs/lemp/` (D12): `fiducial_int_gen.v` with its test, `timing_core_local.v`, `triggers.v`.
   - Generic, into shared blocks: `buf_delay` and 32-bit pulse fields, LEMP register naming (D11), and the `cic_waves` `buf_trig` change reconciled with main's `cbuf_free_run`.
2. **Build `designs/lemp/llrf_shell.sv` on main** from the shared blocks (`SIG_BUF_AW=10` and the `iq_buf` alias, D1), plus LEMP's ports, interlock, timing, triggers and readback. Fix L1–L5. Replace the current `designs/lemp` symlinks.
   Build **`top/lemp/`** (§2.8): `design_io.vh` (HDMI `OBUFDS`, PMOD, SSSB, fiber), `design_mid.vh` (`interlock_wrapper` @ segment 2), `design.xdc`, `fiber_top.v` + `gtp_config/`, `flash.sh`. Move `interlock/` to `designs/lemp/interlock/`.
3. **Port LEMP's `test_llrf_shell.py` deltas** into the LEMP TB subclass. Use LEMP hardware logs as the reference for the trigger and interlock behavior.
4. **Merge main into the LEMP branch.** For `llrf_dsp/llrf_shell.v`, `static_regmap.json` and `top/marble_zest/*`, take main's side; they are replaced by `designs/lemp` and `top/lemp`. Keep LEMP's Python scripts, and move the plotting ones under `uspas_llrf/app/` or `tools/`.
5. **Hardware check** on the LEMP Marble (`make -C top/lemp system_config MARBLE_SERIAL=<n>`). Then retire the shell copy on the LEMP branch.

Deferred (D13): `LEMP_bypass` (klystron reverse interlock bypass), `LEMP_LCLSI_upgrade` and `LEMP_dac_sweep`. Once `designs/lemp` exists, `bypass` will most likely become a LEMP shell feature.

### 3.2 ALSU (`alsu_fork`)

`alsu_fork` sits directly on top of current main (2 commits), so it is merged **early** (step 3), before the shell refactor. Its features then flow into the new blocks like everything else.

1. **Merge `alsu_fork` into `cleanup_llrf_shell`**, then immediately re-home the ALSU-specific pieces:
   - top IO mapping (PMOD1 ARC, PMOD2 FO board) → `top/alsu/design_mid.vh`; the base `marble_zest_mid.vh` returns to main's wiring
   - Modbus UART1 → SoC expansion port, with `rs485_uart` instantiated in `top/alsu/design_mid.vh` (§2.9)
   - Modbus firmware, `mb_addr_map.toml`, `BLOCK_RAM_SIZE=65536`, `ZEST_BYPASS_AD7794_READS` → `soc/alsu/`
   - `test_scripts/` → `designs/alsu/scripts/`; the Modbus tests stay runnable against hardware
   - `.gitlab-ci.yml`: drop the fork-only matrix. Use a per-design matrix (`top/<design>`); `alsu_run` stays and the other `*_run` jobs are re-enabled.
2. **Shared upgrades for all designs:**
   - the new `arc_inlk` (fix A1–A3) and the `llrf_shell_skin.v` permit ports
   - `localBusAddressMap.py` (array unroll), the `gen_init_reg.py` fix and the `llrf.c` `_0` names
   - the `pyproject.toml` dependencies and the bedrock bump, after checking every design still builds
3. **`phase_ramp`** moves to `designs/alsu/phase_ramp.v` **as-is**, with only PR1–PR2 applied (D19), and `phase_ramp_tb.v` is kept. It is wired into ALSU's own thin shell in step 7. Until then ALSU runs the base shell without it, exactly like `alsu_fork` today.
4. **Verify:**
   - non-ALSU designs reproduce their step-1 baselines, except for the new `arc_*` registers
   - ALSU matches an `alsu_fork` build in utilization, `report_io` and `llrf_shell.json`, plus the Modbus register map
   - hardware check through the `alsu_run` CI job ⚠ R7

---

## 4. Sequencing (one MR each, CI green)

1. **Baseline:** results for all design tbs, CDC, and Vivado utilization/timing, plus `report_io` and the config ROM JSON per design. **Archive each design's newad `llrf_shell.json`** under `designs/<d>/_baseline/`. For ALSU, take the baseline from an **`alsu_fork` build** (it is the deployed state), including the generated Modbus header. For LEMP, take it from the **LEMP branch** (`llrf_dsp/llrf_shell.json` at 2e25cd9, bedrock 235f3e3; 187 registers including `iq_buf`), not from `designs/lemp` on main, which is a uspas copy (replaced 2026-10-09). ⚠ R2, R6
2. **Per-design top and SoC** (§2.8, §2.9):
   - `top/common/` plus thin `top/{uspas,alsu,lemp,awa,pip-ii}/` with the override hooks and per-design `_xilinx/`
   - `soc/common/` plus `soc/<design>/` with `design.mk` and `settings_design.h`; move the `init_*_<FSET>.c` files (the SoC expansion port and firmware hooks move to step 3)
   - forwarders left in `top/marble_zest/` and `soc/marble_zest/`

   No RTL change. Each design must reproduce its step-1 baseline. ⚠ R6
3. **ALSU merge-back** (§3.2): add the SoC expansion port and the `design_init()`/`design_irq()`/`design_poll()`/`design_console()` firmware hooks (§2.9), merge `alsu_fork`, then re-home its top IO into `top/alsu/` and Modbus into `soc/alsu/` plus the expansion port. Adopt the upgraded `arc_inlk` (A1–A3) for all designs and the shared SoC tool fixes. Move `phase_ramp` to `designs/alsu/` as-is (PR1–PR2 only). Restore the per-design CI matrix. ⚠ R7
4. **`pulse_gen` extension** (index output, AW+1 `end_val`) with unit tests.
5. **`loop_ctrl`** with amp and phase LUTs on `dpram` and the `phs_offset`/`err` hooks, plus `PulseModulator`, `test_pulse_modulation`, `test_arc_inlk` and unit tests.
6. **Register generator** (§2.4): `regmap.py`, `llrf_shell_regs.sv`, pkg, JSON, sv2v expand rule. Swap it in for newad on the current (still monolithic) shell. It must pass `test_regmap_compat` against the step-1 JSON and the Modbus-name check before any block refactor. ⚠ R2, R3
7. **Package, `lb_if`, `lb_rd_mux`, `rx_chain`, `tx_chain`, `diag`.** Convert `designs/uspas/llrf_shell.sv` to blocks; awa and pip-ii reuse it. Create **`designs/alsu/llrf_shell.sv`** (base blocks plus `phase_ramp` on loop 0, EVR start, through `phs_offset`), the ALSU TB subclass with `test_phase_ramp`, and the `PhaseRamp` model. Apply the naming convention (§2.4.1) in the shell, model, TB, `mb_addr_map.toml` and `designs/alsu/scripts/phase_ramp.py`. ⚠ R5, R7
8. **Bring LEMP pieces to main** (§3.1 step 1): generic ones into blocks, LEMP-only ones into `designs/lemp/`.
9. **`designs/lemp/llrf_shell.sv`, `top/lemp/` and `soc/lemp/`** (`design_io.vh`, `design_mid.vh`, `design.xdc`, fiber/GTP, `interlock/` moved into `designs/lemp/`), plus the LEMP TB subclass. Port the `// auto` trigger regs to array `Reg`s. ⚠ R1, R6
10. **Merge main into the LEMP branch**; hardware check. ⚠ R1, R4
11. **Model/docs cleanup:**
    - READMEs and `doc/developer_guide.md` §2/§5/§6: build entry is now `make -C top/<design>`; describe shared blocks plus per-design shells, tops and SoCs
    - remove the `top/marble_zest` and `soc/marble_zest` forwarders
    - retire `alsu_fork`
    - record §1.2.1 (generic loop modulator) as a follow-up item

## 5. Reminders for future steps

Steps marked ⚠ in §4 depend on these.

| # | Reminder | Applies to |
|---|---|---|
| R1 | **Get the LEMP hardware logs** (trigger timing, interlock-latch / fiducial re-arm, DC-channel captures) before writing the LEMP TB tests. They are the reference for behavior that has no Python model yet. | §3.1 step 3; steps 9–10 |
| R2 | **Archive the baseline newad `llrf_shell.json`** for every design *before* changing any RTL. Without it, `test_regmap_compat` has nothing to compare against. | step 1 → step 6 |
| R3 | **Pin the sv2v version** (v0.0.13-13-g493a88f locally). Add it to `doc/developer_guide.md` required tools and to the CI image. | step 6 |
| R4 | **`LEMP_bypass`, `LEMP_LCLSI_upgrade` and `LEMP_dac_sweep` are deferred** (D13). Revisit once `designs/lemp` lands. | after step 10 |
| R5 | **Register renames (D11) change leep names.** Update `uspas_llrf/app`, EPICS `.bob` screens, `settings.json` consumers, ALSU `mb_addr_map.toml` (`soft_drive_enable`) and `designs/alsu/scripts/` (`phase_ramp_*` → `loop0_phs_ramp_*`) in the same MR, per §2.4.1. | step 7 |
| R6 | **Top-level equivalence needs Vivado on your machine.** Step 2 requires a before/after `report_utilization`, `report_timing_summary` and `report_io` per design. Step 9 needs the same reports from a LEMP-branch build of `top/marble_zest` (DESIGN=lemp) as the reference. | steps 1, 2, 9 |
| R7 | **ALSU hardware check** through the `alsu_run` CI job (`MARBLE_SERIAL`). Modbus (`modbus_test.py`, `app_modbus_test.py`), ARC detector test/reset on PMOD1, and FO-board permits on PMOD2 must behave like `alsu_fork`. | steps 3, 7 |
| R8 | **Generic loop modulator (§1.2.1) is future work.** Do not move ALSU off its `phase_ramp` without a decision and a hardware comparison. | after step 11 |

## 6. Resolved questions (v7, v8)

| Q | Answer | Recorded as |
|---|---|---|
| Phase-ramp register names | `loop0_phs_ramp_*`, consistent with D11 | D21, §2.4.1 |
| Phase-ramp behavior when the loop opens | same as `alsu_fork` today (snap back to `phs_setpoint`) | D19 |
| Phase-ramp trigger / loops | EVR event, loop 0 only; `phase_ramp` stays as-is in `designs/alsu/` until a generic loop modulator exists | D19, §1.2.1, R8 |
| SoC BRAM | 64K for ALSU only | D22 |
| LEMP signal-buffer size (v8, LEMP review) | LEMP keeps `SIG_BUF_AW=10` (1K); the others use 11 (2K) | D1 |
| LEMP one-call I/Q readout (v9, LEMP review) | buffers packed at natural size (no 2K slots), so the I/Q buffers are contiguous; LEMP keeps `iq_buf` with `addr_width` 15 | D1, §1.1, §2.4 |

No open questions remain. Items to confirm during implementation are tracked as reminders R1–R8 (§5).
