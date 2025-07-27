# RTL and Physics Co-Simulation for LLRF

## Getting started

1. Install [`cocotb`](https://docs.cocotb.org/en/stable/install.html) (tested version: 1.9.1) and ['verilator`](https://verilator.org/guide/latest/install.html) (tested version: 5.027);
   ```
   sudo apt install verilator
   pip install cocotb==1.9.1 pytest
   ```

2. Build and run simulation:
   ```
   make
   ```

   The test bench will run 4 frequency configurations: `ALSU`, `USPAS`, `LEMP` and `AWA`. It tests receiver accuracy, open loop and close loop response correspondingly. The DSP transfer functions are modeled in `llrf_dsp.py` and integrated in the test for automated calibration. The RX and TX phase rotation introduced by latency and digital filters are compensated by phase offsets of the digital down / up conversion, so that there is no need for phase calibration in software.
   Typical verification results:

```
     0.00ns INFO     cocotb                             Seeding Python random module with 1738686879
     0.00ns INFO     cocotb.regression                  Found test test_llrf_dsp.test_alsu
     0.00ns INFO     cocotb.regression                  Found test test_llrf_dsp.test_uspas
     0.00ns INFO     cocotb.regression                  Found test test_llrf_dsp.test_lemp
     0.00ns INFO     cocotb.regression                  Found test test_llrf_dsp.test_awa
     0.00ns INFO     cocotb.regression                  running test_alsu (1/4)
     0.00ns INFO     cocotb.llrf_dsp                    ********************  Simulating: ALSU  ********************
     0.00ns INFO     cocotb.llrf_dsp                    RX phase off:   131.75 deg; TX phase off:   -32.73 deg
     0.00ns INFO     cocotb.llrf_dsp                    RX phase off:   191879 cnt; TX phase off:   -47662 cnt
     0.00ns INFO     cocotb.llrf_dsp                    inlk_gain:   0.570886
     0.00ns INFO     cocotb.llrf_dsp                    mon_gain:    5.546751
     0.00ns INFO     cocotb.llrf_dsp                    ********************      RX Test       ********************
     0.00ns INFO     cocotb.llrf_dsp                    LLRFModel RX:
                                                        < DSPCoreRX   :   Amp gain= 2.416,   Phs gain=    0.00 deg >
                                                        WashoutFilter :   Amp gain= 1.032,   Phs gain= -130.07 deg;
                                                        DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                        DDC           :   Amp gain= 1.511,   Phs gain=  -98.18 deg;
                                                        CORDIC        :   Amp gain= 1.647,   Phs gain= -131.75 deg;

  1809.60ns INFO     cocotb.llrf_dsp                    expected mag: 26451.53 cnt,  phs: -123.434 deg
  1818.30ns INFO     cocotb.llrf_dsp                    measured mag: 26450.87 cnt,  phs: -123.437 deg
  1827.00ns INFO     cocotb.llrf_dsp                    measured mag: 26450.87 cnt,  phs: -123.437 deg
  1835.70ns INFO     cocotb.llrf_dsp                    measured mag: 26450.87 cnt,  phs: -123.437 deg
  1844.40ns INFO     cocotb.llrf_dsp                    measured mag: 26450.46 cnt,  phs: -123.434 deg
  1853.10ns INFO     cocotb.llrf_dsp                    measured mag: 26450.46 cnt,  phs: -123.431 deg
  1853.10ns INFO     cocotb.llrf_dsp                    ********************   Open Loop Test   ********************
  1853.10ns INFO     cocotb.llrf_dsp                    LLRFModel TX:
                                                        < DSPCoreTX   :   Amp gain= 0.387,   Phs gain=   -0.00 deg >
                                                        DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                        DUC           :   Amp gain= 0.250,   Phs gain=  -32.73 deg;
                                                        CORDIC        :   Amp gain= 1.647,   Phs gain=   32.73 deg;

  4793.70ns INFO     cocotb.llrf_dsp                    expected mag: 26451.53 cnt,  phs: -18.437 deg
  4802.40ns INFO     cocotb.llrf_dsp                    measured mag: 26452.11 cnt,  phs: -18.436 deg
  4811.10ns INFO     cocotb.llrf_dsp                    measured mag: 26448.80 cnt,  phs: -18.436 deg
  4819.80ns INFO     cocotb.llrf_dsp                    measured mag: 26449.22 cnt,  phs: -18.438 deg
  4828.50ns INFO     cocotb.llrf_dsp                    measured mag: 26449.63 cnt,  phs: -18.441 deg
  4837.20ns INFO     cocotb.llrf_dsp                    measured mag: 26451.70 cnt,  phs: -18.438 deg
  4837.20ns INFO     cocotb.llrf_dsp                    ********************  Close Loop Test   ********************
  4837.20ns INFO     cocotb.llrf_dsp                    Cavity Model:
                                                        Config:            ALSU
                                                        Q_L:             7183.0
                                                        Center freq:      500.4 MHz
                                                        half bandwidth:    34.8 kHz
                                                        F_if:              41.8 MHz
                                                        F_adc:            114.9 MHz
                                                        system_z:      TransferFunctionDiscrete(
                                                        array([ 0.00190041,  0.        , -0.00190041]),
                                                        array([1.        , 1.30723246, 0.99619918]),
                                                        dt: 8.699999999999998e-09
                                                        )
 22454.70ns INFO     cocotb.llrf_dsp                    expected mag: 23806.38 cnt,  phs: -63.843 deg
 22463.40ns INFO     cocotb.llrf_dsp                    measured mag: 23807.28 cnt,  phs: -63.839 deg
 22472.10ns INFO     cocotb.llrf_dsp                    measured mag: 23807.28 cnt,  phs: -63.839 deg
 22480.80ns INFO     cocotb.llrf_dsp                    measured mag: 23806.03 cnt,  phs: -63.840 deg
 22489.50ns INFO     cocotb.llrf_dsp                    measured mag: 23805.21 cnt,  phs: -63.843 deg
 22498.20ns INFO     cocotb.llrf_dsp                    measured mag: 23805.21 cnt,  phs: -63.847 deg
 22498.20ns INFO     cocotb.regression                  test_alsu passed
 22498.20ns INFO     cocotb.regression                  running test_uspas (2/4)
 22498.20ns INFO     cocotb.llrf_dsp                    ******************** Simulating: USPAS  ********************
 22498.20ns INFO     cocotb.llrf_dsp                    RX phase off:    65.65 deg; TX phase off:   172.17 deg
 22498.20ns INFO     cocotb.llrf_dsp                    RX phase off:    95602 cnt; TX phase off:   250746 cnt
 22498.20ns INFO     cocotb.llrf_dsp                    inlk_gain:   0.732108
 22498.20ns INFO     cocotb.llrf_dsp                    mon_gain:    7.113198
 22498.20ns INFO     cocotb.llrf_dsp                    ********************      RX Test       ********************
 22498.20ns INFO     cocotb.llrf_dsp                    LLRFModel RX:
                                                        < DSPCoreRX   :   Amp gain= 2.834,   Phs gain=    0.00 deg >
                                                        WashoutFilter :   Amp gain= 1.031,   Phs gain=  -59.57 deg;
                                                        DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                        DDC           :   Amp gain= 1.776,   Phs gain=  125.22 deg;
                                                        CORDIC        :   Amp gain= 1.647,   Phs gain=  -65.65 deg;

 24299.10ns INFO     cocotb.llrf_dsp                    expected mag: 22544.21 cnt,  phs: 47.372 deg
 24307.80ns INFO     cocotb.llrf_dsp                    measured mag: 22544.00 cnt,  phs: 47.372 deg
 24316.50ns INFO     cocotb.llrf_dsp                    measured mag: 22544.00 cnt,  phs: 47.368 deg
 24325.20ns INFO     cocotb.llrf_dsp                    measured mag: 22542.94 cnt,  phs: 47.370 deg
 24333.90ns INFO     cocotb.llrf_dsp                    measured mag: 22542.23 cnt,  phs: 47.373 deg
 24342.60ns INFO     cocotb.llrf_dsp                    measured mag: 22542.94 cnt,  phs: 47.372 deg
 24342.60ns INFO     cocotb.llrf_dsp                    ********************   Open Loop Test   ********************
 24342.60ns INFO     cocotb.llrf_dsp                    LLRFModel TX:
                                                        < DSPCoreTX   :   Amp gain= 0.387,   Phs gain=   -0.00 deg >
                                                        DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                        DUC           :   Amp gain= 0.250,   Phs gain=  172.17 deg;
                                                        CORDIC        :   Amp gain= 1.647,   Phs gain= -172.17 deg;

 27239.70ns INFO     cocotb.llrf_dsp                    expected mag: 22544.21 cnt,  phs: 12.404 deg
 27248.40ns INFO     cocotb.llrf_dsp                    measured mag: 22544.00 cnt,  phs: 12.404 deg
 27257.10ns INFO     cocotb.llrf_dsp                    measured mag: 22545.06 cnt,  phs: 12.404 deg
 27265.80ns INFO     cocotb.llrf_dsp                    measured mag: 22544.00 cnt,  phs: 12.404 deg
 27274.50ns INFO     cocotb.llrf_dsp                    measured mag: 22542.59 cnt,  phs: 12.405 deg
 27283.20ns INFO     cocotb.llrf_dsp                    measured mag: 22544.00 cnt,  phs: 12.406 deg
 27283.20ns INFO     cocotb.llrf_dsp                    ********************  Close Loop Test   ********************
 27283.20ns INFO     cocotb.llrf_dsp                    Cavity Model:
                                                        Config:           USPAS
                                                        Q_L:             4181.2
                                                        Center freq:      499.7 MHz
                                                        half bandwidth:    59.8 kHz
                                                        F_if:              20.0 MHz
                                                        F_adc:            114.9 MHz
                                                        system_z:      TransferFunctionDiscrete(
                                                        array([ 0.00325558,  0.        , -0.00325558]),
                                                        array([ 1.        , -0.91713452,  0.99348884]),
                                                        dt: 8.699999999999998e-09
                                                        )
 45057.30ns INFO     cocotb.llrf_dsp                    expected mag: 20289.79 cnt,  phs: 61.127 deg
 45066.00ns INFO     cocotb.llrf_dsp                    measured mag: 20290.20 cnt,  phs: 61.124 deg
 45074.70ns INFO     cocotb.llrf_dsp                    measured mag: 20290.20 cnt,  phs: 61.125 deg
 45083.40ns INFO     cocotb.llrf_dsp                    measured mag: 20289.49 cnt,  phs: 61.128 deg
 45092.10ns INFO     cocotb.llrf_dsp                    measured mag: 20288.79 cnt,  phs: 61.131 deg
 45100.80ns INFO     cocotb.llrf_dsp                    measured mag: 20290.20 cnt,  phs: 61.128 deg
 45100.80ns INFO     cocotb.regression                  test_uspas passed
 45100.80ns INFO     cocotb.regression                  running test_lemp (3/4)
 45100.80ns INFO     cocotb.llrf_dsp                    ********************  Simulating: LEMP  ********************
 45100.80ns INFO     cocotb.llrf_dsp                    RX phase off:    79.46 deg; TX phase off:   128.57 deg
 45100.80ns INFO     cocotb.llrf_dsp                    RX phase off:   115720 cnt; TX phase off:   187245 cnt
 45100.80ns INFO     cocotb.llrf_dsp                    inlk_gain:   0.596041
 45100.80ns INFO     cocotb.llrf_dsp                    mon_gain:   11.582334
 45100.80ns INFO     cocotb.llrf_dsp                    ********************      RX Test       ********************
 45100.80ns INFO     cocotb.llrf_dsp                    LLRFModel RX:
                                                        < DSPCoreRX   :   Amp gain= 3.114,   Phs gain=   -0.00 deg >
                                                        WashoutFilter :   Amp gain= 1.031,   Phs gain=  -74.83 deg;
                                                        DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                        DDC           :   Amp gain= 1.950,   Phs gain=  154.29 deg;
                                                        CORDIC        :   Amp gain= 1.647,   Phs gain=  -79.46 deg;

 46798.41ns INFO     cocotb.llrf_dsp                    expected mag: 20519.38 cnt,  phs: 95.821 deg
 46806.81ns INFO     cocotb.llrf_dsp                    measured mag: 20520.47 cnt,  phs: 95.821 deg
 46815.22ns INFO     cocotb.llrf_dsp                    measured mag: 20519.18 cnt,  phs: 95.821 deg
 46823.62ns INFO     cocotb.llrf_dsp                    measured mag: 20518.22 cnt,  phs: 95.820 deg
 46832.03ns INFO     cocotb.llrf_dsp                    measured mag: 20518.22 cnt,  phs: 95.824 deg
 46840.43ns INFO     cocotb.llrf_dsp                    measured mag: 20518.54 cnt,  phs: 95.826 deg
 46840.43ns INFO     cocotb.llrf_dsp                    ********************   Open Loop Test   ********************
 46840.43ns INFO     cocotb.llrf_dsp                    LLRFModel TX:
                                                        < DSPCoreTX   :   Amp gain= 0.387,   Phs gain=   -0.00 deg >
                                                        DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                        DUC           :   Amp gain= 0.250,   Phs gain=  128.57 deg;
                                                        CORDIC        :   Amp gain= 1.647,   Phs gain= -128.57 deg;

 49588.54ns INFO     cocotb.llrf_dsp                    expected mag: 20519.38 cnt,  phs: 51.640 deg
 49596.94ns INFO     cocotb.llrf_dsp                    measured mag: 20518.54 cnt,  phs: 51.638 deg
 49605.35ns INFO     cocotb.llrf_dsp                    measured mag: 20519.51 cnt,  phs: 51.638 deg
 49613.75ns INFO     cocotb.llrf_dsp                    measured mag: 20520.15 cnt,  phs: 51.637 deg
 49622.15ns INFO     cocotb.llrf_dsp                    measured mag: 20518.54 cnt,  phs: 51.638 deg
 49630.56ns INFO     cocotb.llrf_dsp                    measured mag: 20517.26 cnt,  phs: 51.640 deg
 49630.56ns INFO     cocotb.llrf_dsp                    ********************  Close Loop Test   ********************
 49630.56ns INFO     cocotb.llrf_dsp                    Cavity Model:
                                                        Config:            LEMP
                                                        Q_L:             1818.2
                                                        Center freq:     2856.0 MHz
                                                        half bandwidth:   785.4 kHz
                                                        F_if:              25.5 MHz
                                                        F_adc:            119.0 MHz
                                                        system_z:      TransferFunctionDiscrete(
                                                        array([ 0.03982072,  0.        , -0.03982072]),
                                                        array([ 1.        , -0.42731998,  0.92035855]),
                                                        dt: 8.404e-09
                                                        )
 66774.72ns INFO     cocotb.llrf_dsp                    expected mag: 18467.44 cnt,  phs: 74.590 deg
 66783.12ns INFO     cocotb.llrf_dsp                    measured mag: 18467.49 cnt,  phs: 74.590 deg
 66791.53ns INFO     cocotb.llrf_dsp                    measured mag: 18467.49 cnt,  phs: 74.593 deg
 66799.93ns INFO     cocotb.llrf_dsp                    measured mag: 18467.17 cnt,  phs: 74.588 deg
 66808.33ns INFO     cocotb.llrf_dsp                    measured mag: 18466.85 cnt,  phs: 74.583 deg
 66816.74ns INFO     cocotb.llrf_dsp                    measured mag: 18466.53 cnt,  phs: 74.588 deg
 66816.74ns INFO     cocotb.regression                  test_lemp passed
 66816.74ns INFO     cocotb.regression                  running test_awa (4/4)
 66816.74ns INFO     cocotb.llrf_dsp                    ********************  Simulating: AWA   ********************
 66816.74ns INFO     cocotb.llrf_dsp                    RX phase off:    78.71 deg; TX phase off:   130.91 deg
 66816.74ns INFO     cocotb.llrf_dsp                    RX phase off:   114633 cnt; TX phase off:   190650 cnt
 66816.74ns INFO     cocotb.llrf_dsp                    inlk_gain:   0.824394
 66816.74ns INFO     cocotb.llrf_dsp                    mon_gain:   16.019706
 66816.74ns INFO     cocotb.llrf_dsp                    ********************      RX Test       ********************
 66816.74ns INFO     cocotb.llrf_dsp                    LLRFModel RX:
                                                        < DSPCoreRX   :   Amp gain= 3.101,   Phs gain=   -0.00 deg >
                                                        WashoutFilter :   Amp gain= 1.031,   Phs gain=  -74.01 deg;
                                                        DDS           :   Amp gain= 0.939,   Phs gain=    0.00 deg;
                                                        DDC           :   Amp gain= 1.944,   Phs gain=  152.73 deg;
                                                        CORDIC        :   Amp gain= 1.647,   Phs gain=  -78.71 deg;

 69128.85ns INFO     cocotb.llrf_dsp                    expected mag: 20607.13 cnt,  phs: -97.379 deg
 69139.45ns INFO     cocotb.llrf_dsp                    measured mag: 20606.29 cnt,  phs: -97.381 deg
 69150.06ns INFO     cocotb.llrf_dsp                    measured mag: 20606.29 cnt,  phs: -97.381 deg
 69160.66ns INFO     cocotb.llrf_dsp                    measured mag: 20606.29 cnt,  phs: -97.381 deg
 69171.27ns INFO     cocotb.llrf_dsp                    measured mag: 20606.61 cnt,  phs: -97.379 deg
 69181.88ns INFO     cocotb.llrf_dsp                    measured mag: 20607.26 cnt,  phs: -97.377 deg
 69181.88ns INFO     cocotb.llrf_dsp                    ********************   Open Loop Test   ********************
 69181.88ns INFO     cocotb.llrf_dsp                    LLRFModel TX:
                                                        < DSPCoreTX   :   Amp gain= 0.387,   Phs gain=    0.00 deg >
                                                        DDS           :   Amp gain= 0.939,   Phs gain=    0.00 deg;
                                                        DUC           :   Amp gain= 0.250,   Phs gain=  130.91 deg;
                                                        CORDIC        :   Amp gain= 1.647,   Phs gain= -130.91 deg;

 72713.68ns INFO     cocotb.llrf_dsp                    expected mag: 20607.13 cnt,  phs: 39.045 deg
 72724.28ns INFO     cocotb.llrf_dsp                    measured mag: 20607.58 cnt,  phs: 39.047 deg
 72734.89ns INFO     cocotb.llrf_dsp                    measured mag: 20607.58 cnt,  phs: 39.044 deg
 72745.49ns INFO     cocotb.llrf_dsp                    measured mag: 20607.58 cnt,  phs: 39.043 deg
 72756.10ns INFO     cocotb.llrf_dsp                    measured mag: 20607.26 cnt,  phs: 39.044 deg
 72766.71ns INFO     cocotb.llrf_dsp                    measured mag: 20606.94 cnt,  phs: 39.044 deg
 72766.71ns INFO     cocotb.llrf_dsp                    ********************  Close Loop Test   ********************
 72766.71ns INFO     cocotb.llrf_dsp                    Cavity Model:
                                                        Config:             AWA
                                                        Q_L:            10666.7
                                                        Center freq:     1300.0 MHz
                                                        half bandwidth:    60.9 kHz
                                                        F_if:              20.0 MHz
                                                        F_adc:             94.3 MHz
                                                        system_z:      TransferFunctionDiscrete(
                                                        array([ 0.00404442,  0.        , -0.00404442]),
                                                        array([ 1.        , -0.46961086,  0.99191116]),
                                                        dt: 1.0606e-08
                                                        )
 94381.73ns INFO     cocotb.llrf_dsp                    expected mag: 18546.42 cnt,  phs: 12.014 deg
 94392.34ns INFO     cocotb.llrf_dsp                    measured mag: 18546.47 cnt,  phs: 12.011 deg
 94402.95ns INFO     cocotb.llrf_dsp                    measured mag: 18547.44 cnt,  phs: 12.008 deg
 94413.55ns INFO     cocotb.llrf_dsp                    measured mag: 18546.15 cnt,  phs: 12.012 deg
 94424.16ns INFO     cocotb.llrf_dsp                    measured mag: 18544.86 cnt,  phs: 12.016 deg
 94434.76ns INFO     cocotb.llrf_dsp                    measured mag: 18545.82 cnt,  phs: 12.015 deg
 94434.76ns INFO     cocotb.regression                  test_awa passed
 94434.76ns INFO     cocotb.regression                  **************************************************************************************
                                                        ** TEST                          STATUS  SIM TIME (ns)  REAL TIME (s)  RATIO (ns/s) **
                                                        **************************************************************************************
                                                        ** test_llrf_dsp.test_alsu        PASS       22498.20           1.33      16925.86  **
                                                        ** test_llrf_dsp.test_uspas       PASS       22602.60           1.33      16993.87  **
                                                        ** test_llrf_dsp.test_lemp        PASS       21715.94           1.57      13855.98  **
                                                        ** test_llrf_dsp.test_awa         PASS       27618.02           1.49      18596.45  **
                                                        **************************************************************************************
                                                        ** TESTS=4 PASS=4 FAIL=0 SKIP=0              94434.76           6.54      14429.37  **
                                                        **************************************************************************************
```

3. Check waveform:
   ```
   gtkwave dump.fst dump.gtkw
   ```
   Typical result:
   ![waveform](../../doc/fig/waveform_example.png)
