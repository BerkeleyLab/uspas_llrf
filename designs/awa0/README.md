# AWA0 Facility DSP Configuration

This directory contains the legacy / baseline DSP configuration and static register mapping for the **Argonne Wakefield Accelerator (AWA0)** setup.

## Design Architecture & Shell Flavor

- **Frequency Configuration (`FSET`)**: `AWA`
- **`llrf_shell.v` Flavor**: **Baseline** (symbolic link to `../uspas/llrf_shell.v`)
- **`static_regmap.json`**: Symbolic link to `../uspas/static_regmap.json`
- **Testbench**: Uses unified cocotb runner `tb/llrf_shell/` based on `uspas_llrf.tests.test_llrf_shell.TB_llrf_shell`.

---

## Frequency and Clocking Summary

| Signal | Ratio | Frequency | Unit |
| :---: | :---: | :---: | :---: |
| Master Oscillator (MO) | - | 1300.000 | MHz |
| Local Oscillator (LO) | MO / 65 * 66 | 1320.000 | MHz |
| DSP Clock (`dsp_clk`) | LO / 14 | 94.286 | MHz |
| DAC Clock (`dac_clk`) | LO / 7 | 188.571 | MHz |
| ADC IF (`IF_adc`) | MO / 65 | 20.000 | MHz |
| DAC IF (`IF_dac`) | LO / 264 * 29 | 145.000 | MHz |
| ADC IF / `dsp_clk` | 7 / 33 | - | - |
| DAC IF / `dac_clk` | 203 / 264 | - | - |

- **Zest Reference Clock**: LO (1320 MHz)
- **DAC Mode**: Mix-Mode (2nd Nyquist zone operation with spectral flip)

---

## Simplified DSP Architecture

```mermaid
flowchart LR
    subgraph RX_Path["Receiver Path (ADC x8)"]
        ADC["ADC Raw Inputs<br/>(8 Channels)"] --> WASH["DC Washout Filter"]
        WASH --> DDC["Non-IQ DDC"]
        RX_DDS["RX DDS NCO<br/>(7/33 @ dsp_clk)"] --> DDC
        DDC --> IQ_BB["I, Q Baseband"]
        IQ_BB --> RX_CORDIC["RX CORDIC<br/>(Cartesian -> Polar)"]
        RX_CORDIC --> AMP_PHS["Amp, Phase"]
    end

    subgraph Control_Loops["Dual PI Feedback Loops"]
        AMP_PHS --> PI0["PI Loop 0<br/>(Pulsed Amp & Phase PI, ADC Ch 3)"]
        AMP_PHS --> PI1["PI Loop 1<br/>(Pulsed Amp & Phase PI, ADC Ch 3)"]
        PI0 --> DRIVE["Baseband Drive (I0, I1)"]
        PI1 --> DRIVE
    end

    subgraph TX_Path["Transmitter Path (DAC x2 - 2nd Nyquist)"]
        DRIVE --> TX_CORDIC["TX CORDIC<br/>(Phase Offset Compensate)"]
        TX_CORDIC --> DUC["2x Interpolation & DUC<br/>(Spectral Inversion)"]
        TX_DDS["TX DDS NCO<br/>(203/264 @ dac_clk)"] --> DUC
        DUC --> DAC["DAC Outputs<br/>(2 Channels, I0/I1 drive)"]
    end

    subgraph Diagnostics["Diagnostics & Interlocks"]
        IQ_BB --> RAW_BUF["Raw & IQ Buffers<br/>(2k samples / ch, 0x1000 stride)"]
        DRIVE --> RAW_BUF
        IQ_BB --> CIC["CIC Decimation<br/>Recorder (Base Period 33)"]
        DRIVE --> CIC
        CIC --> CBUF["Circular Buffer<br/>(64k x 24-bit)"]
        IQ_BB --> INLK["Fast Interlock Monitor<br/>& RF Permit Latch"]
    end
```

---

## DSP Configuration & Calibration Factors

### `dsp_config['AWA']`
```python
{
    'DSP_CLK_CYCLE': 10.6,          # ns (~94.286 MHz)
    'LO_AMP': 74762,                # DDS LO Amplitude
    'NUM_DDS': 7,                   # RX DDS Numerator
    'DEN_DDS': 33,                  # RX DDS Denominator (IF/Fs = 7/33)
    'TX_NUM_DDS': 203,              # TX DDS Numerator
    'TX_DEN_DDS': 264,              # TX DDS Denominator (IF/Fs = 203/264)
    'TX_SECOND_NYQUIST': True,      # 2nd Nyquist zone enabled
    'CIC_BASE_PERIOD': 33,          # CIC base decimation period
    'CIC_SHIFT_BASE': 7,
    'INLK_SHIFT_BASE': 11,
    'INLK_SHIFT_ADD': 1,
    'PRL_ADC_CHAN': 0,              # Phase reference ADC channel
    'LOOP0_ADC_CHAN': 3,            # Feedback ADC channel for Loop 0
    'LOOP1_ADC_CHAN': 3,            # Feedback ADC channel for Loop 1
    'DAC_DRIVE_SEL': 2,             # 2: I0I1 mode
    'PULSE_MODES': 3,               # Pulsed mode enabled
    'EVCODE': 151
}
```

### Calibration Factors
- **`rx_gain`**: `3.100752`
- **`tx_gain`**: `1.546791`
- **`rx_phase_off_deg`**: `2.3489 degree`
- **`tx_phase_off_deg`**: `165.0000 degree`
- **`rx_dds_omega_deg`**: `76.3636 degree`
- **`tx_dds_omega_deg`**: `276.8182 degree`
- **`cic_wfm_gain`**: `8.009853`
- **`inlk_gain`**: `0.824394`
- **`inlk_tx_gain`**: `0.279335 - 0.373148j`
- **`rx_iq_gain`**: `1.882941`
- **`tx_iq_gain`**: `0.562898 + 0.751943j`
- **`max_amp_setpoint`**: `20125`

---

## Memory Map & Static Registers

### Static Buffers (11-bit depth = 2048 samples, 0x1000 stride mapping)
| Buffer Name | Base Address (Hex) | Word Width | Access | Description |
| :--- | :---: | :---: | :---: | :--- |
| `adc0_buf` .. `adc7_buf` | `0x12000` - `0x19000` | 16-bit signed | R | Raw ADC waveform buffers (2k words each, stride `0x1000`) |
| `adc0_i_buf` .. `adc7_i_buf` | `0x1c000` - `0x23000` | 18-bit signed | R | ADC demodulated In-phase buffers (stride `0x1000`) |
| `drv0_i_buf`, `drv1_i_buf` | `0x24000`, `0x25000` | 18-bit signed | R | DAC drive In-phase buffers |
| `adc0_q_buf` .. `adc7_q_buf` | `0x26000` - `0x2d000` | 18-bit signed | R | ADC demodulated Quadrature buffers (stride `0x1000`) |
| `drv0_q_buf`, `drv1_q_buf` | `0x2e000`, `0x2f000` | 18-bit signed | R | DAC drive Quadrature buffers |
| `circle_data` | `0x30000` | 24-bit signed | R | Circular buffer waveform recorder (64k depth) |

### Status & Diagnostic Registers
| Register Name | Base Address (Hex) | Width / Sign | Access | Description |
| :--- | :---: | :---: | :---: | :--- |
| `llrf_circle_ready` | `0x10800` | 2-bit unsigned | R | Circular buffer status |
| `sig_buf_ready` | `0x10801` | 8-bit unsigned | R | Raw ADC buffers ready mask |
| `sig_iq_buf_ready` | `0x10802` | 20-bit unsigned | R | IQ buffers ready mask |
| `dsp_slow_data` | `0x10900` | 16-bit unsigned | R | Slow bridge streaming data |
| `mon_amp` | `0x10a00` | 16-bit signed (x16) | R | Channel amplitude monitor array |
| `mon_phs` | `0x10a10` | 17-bit signed (x16) | R | Channel phase monitor array |
| `rf_pwr_status` / `latch` | `0x00003` / `0x00005`| 10-bit unsigned | R | RF power interlock status and latched bits |
| `arc_permit_sum` | `0x00009` | 1-bit unsigned | R | ARC interlock overall permit |
| `loop0_amp_err`, `phs_err` | `0x0000a`, `0x0000b` | 15-bit signed | R | Loop 0 amplitude and phase error monitors |
| `loop1_amp_err`, `phs_err` | `0x0000c`, `0x0000d` | 15-bit signed | R | Loop 1 amplitude and phase error monitors |
| `evr_live_ts_lo` / `hi` | `0x00020` / `0x00021` | 32-bit unsigned | R | EVR live 64-bit timestamp |

### Control & Configuration Registers (Mapped to `0x11000`+)
| Register Name | Width / Sign | Access | Description |
| :--- | :---: | :---: | :--- |
| `rx_dds_phase_step` | 32-bit unsigned | RW | RX DDS NCO phase increment (`911053668`) |
| `rx_dds_phase_shift` | 19-bit signed | RW | RX DDS CORDIC phase offset (`3420`) |
| `rx_dds_modulo` | 12-bit unsigned | RW | RX DDS phase accumulator modulo (`4`) |
| `rx_dds_amplitude` | 18-bit unsigned | RW | RX DDS LO amplitude (`74762`) |
| `tx_dds_phase_step` | 32-bit unsigned | RW | TX DDS NCO phase increment (`3302569496`) |
| `tx_dds_phase_shift` | 19-bit signed | RW | TX DDS CORDIC phase offset (`240298`) |
| `tx_dds_modulo` | 12-bit unsigned | RW | TX DDS phase accumulator modulo (`136`) |
| `tx_dds_amplitude` | 18-bit unsigned | RW | TX DDS LO amplitude (`74762`) |
| `duc_spectral_flip` | 1-bit unsigned | RW | DUC spectral inversion for 2nd Nyquist (`1`) |
| `tx_phase_offset` | 19-bit signed | RW | TX baseband phase compensation (`-77451`) |
| `loop0_amp_setpoint` | 18-bit signed | RW | Loop 0 Amplitude setpoint |
| `loop0_phs_setpoint` | 18-bit signed | RW | Loop 0 Phase setpoint |
| `loop0_pulse_start` | 24-bit unsigned | RW | Loop 0 pulse modulation start time |
| `loop0_pulse_high_len` | 24-bit unsigned | RW | Loop 0 pulse width length |
| `pulse_modes` | 2-bit unsigned | RW | Pulse mode enable (`3`) |
| `wave_samp_per` | 7-bit unsigned | RW | CIC decimation multiplier (default `1`) |
| `chan_keep` | 10-bit unsigned | RW | Bitmask of captured channels in circular buffer |
| `dac_drive_sel` | 2-bit unsigned | RW | DAC multiplexer selection (`2`: I0I1) |
| `prl_adc_chan` | 3-bit unsigned | RW | Phase reference channel (`0`) |
| `loop0_adc_chan`, `loop1_adc_chan` | 3-bit unsigned | RW | Loop 0/1 feedback channel (`3`) |
| `evcode` | 8-bit unsigned | RW | Event receiver trigger code (`151`) |
