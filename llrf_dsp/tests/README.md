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
     0.00ns INFO     cocotb                             Seeding Python random module with 1727736018
     0.00ns INFO     cocotb.regression                  Found test test_dsp_core.test_alsu
     0.00ns INFO     cocotb.regression                  Found test test_dsp_core.test_uspas
     0.00ns INFO     cocotb.regression                  Found test test_dsp_core.test_lemp
     0.00ns INFO     cocotb.regression                  Found test test_dsp_core.test_awa
     0.00ns INFO     cocotb.regression                  running test_alsu (1/4)
     0.00ns INFO     cocotb.dsp_core                    ********************  Simulating: ALSU  ********************
     0.00ns INFO     cocotb.dsp_core                    RX phase off:   131.75 deg; TX phase off:   -32.73 deg
     0.00ns INFO     cocotb.dsp_core                    RX phase off:   191879 cnt; TX phase off:   -47662 cnt
     0.00ns INFO     cocotb.dsp_core                    ********************      RX Test       ********************
     0.00ns INFO     cocotb.dsp_core                    LLRFModel RX:
                                                        < DSPCoreRX   :   Amp gain= 4.831,   Phs gain=    0.00 deg >
                                                        WashoutFilter :   Amp gain= 1.032,   Phs gain= -130.07 deg;
                                                        DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                        DDC           :   Amp gain= 3.023,   Phs gain=  -98.18 deg;
                                                        CORDIC        :   Amp gain= 1.647,   Phs gain= -131.75 deg;

  1226.70ns INFO     cocotb.dsp_core                    expected mag: 26451.53 cnt,  phs: 87.839 deg
  1235.40ns INFO     cocotb.dsp_core                    measured mag: 26450.46 cnt,  phs: 87.834 deg
  1244.10ns INFO     cocotb.dsp_core                    measured mag: 26450.67 cnt,  phs: 87.833 deg
  1252.80ns INFO     cocotb.dsp_core                    measured mag: 26450.87 cnt,  phs: 87.832 deg
  1261.50ns INFO     cocotb.dsp_core                    measured mag: 26450.87 cnt,  phs: 87.838 deg
  1270.20ns INFO     cocotb.dsp_core                    measured mag: 26450.87 cnt,  phs: 87.845 deg
  1270.20ns INFO     cocotb.dsp_core                    ********************   Open Loop Test   ********************
  1270.20ns INFO     cocotb.dsp_core                    LLRFModel TX:
                                                        < DSPCoreTX   :   Amp gain= 0.387,   Phs gain=   -0.00 deg >
                                                        DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                        DUC           :   Amp gain= 0.250,   Phs gain=  -32.73 deg;
                                                        CORDIC        :   Amp gain= 1.647,   Phs gain=   32.73 deg;

  4176.00ns INFO     cocotb.dsp_core                    expected mag: 26451.53 cnt,  phs: -19.939 deg
  4184.70ns INFO     cocotb.dsp_core                    measured mag: 26451.91 cnt,  phs: -19.937 deg
  4193.40ns INFO     cocotb.dsp_core                    measured mag: 26449.84 cnt,  phs: -19.937 deg
  4202.10ns INFO     cocotb.dsp_core                    measured mag: 26450.25 cnt,  phs: -19.939 deg
  4210.80ns INFO     cocotb.dsp_core                    measured mag: 26450.46 cnt,  phs: -19.939 deg
  4219.50ns INFO     cocotb.dsp_core                    measured mag: 26452.11 cnt,  phs: -19.937 deg
  4219.50ns INFO     cocotb.dsp_core                    ********************  Close Loop Test   ********************
  4219.50ns INFO     cocotb.dsp_core                    Cavity Model:
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
 21897.90ns INFO     cocotb.dsp_core                    expected mag: 23806.38 cnt,  phs: 117.825 deg
 21906.60ns INFO     cocotb.dsp_core                    measured mag: 23807.48 cnt,  phs: 117.828 deg
 21915.30ns INFO     cocotb.dsp_core                    measured mag: 23807.28 cnt,  phs: 117.826 deg
 21924.00ns INFO     cocotb.dsp_core                    measured mag: 23807.07 cnt,  phs: 117.824 deg
 21932.70ns INFO     cocotb.dsp_core                    measured mag: 23805.21 cnt,  phs: 117.822 deg
 21941.40ns INFO     cocotb.dsp_core                    measured mag: 23803.55 cnt,  phs: 117.819 deg
 21941.40ns INFO     cocotb.regression                  test_alsu passed
 21941.40ns INFO     cocotb.regression                  running test_uspas (2/4)
 21941.40ns INFO     cocotb.dsp_core                    ******************** Simulating: USPAS  ********************
 21941.40ns INFO     cocotb.dsp_core                    RX phase off:    65.65 deg; TX phase off:   172.17 deg
 21941.40ns INFO     cocotb.dsp_core                    RX phase off:    95602 cnt; TX phase off:   250746 cnt
 21941.40ns INFO     cocotb.dsp_core                    ********************      RX Test       ********************
 21941.40ns INFO     cocotb.dsp_core                    LLRFModel RX:
                                                        < DSPCoreRX   :   Amp gain= 5.669,   Phs gain=    0.00 deg >
                                                        WashoutFilter :   Amp gain= 1.031,   Phs gain=  -59.57 deg;
                                                        DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                        DDC           :   Amp gain= 3.552,   Phs gain=  125.22 deg;
                                                        CORDIC        :   Amp gain= 1.647,   Phs gain=  -65.65 deg;

 23237.70ns INFO     cocotb.dsp_core                    expected mag: 22544.21 cnt,  phs: 145.428 deg
 23246.40ns INFO     cocotb.dsp_core                    measured mag: 22535.35 cnt,  phs: 145.438 deg
 23255.10ns INFO     cocotb.dsp_core                    measured mag: 22548.76 cnt,  phs: 145.452 deg
 23263.80ns INFO     cocotb.dsp_core                    measured mag: 22562.17 cnt,  phs: 145.469 deg
 23272.50ns INFO     cocotb.dsp_core                    measured mag: 22546.82 cnt,  phs: 145.423 deg
 23281.20ns INFO     cocotb.dsp_core                    measured mag: 22531.30 cnt,  phs: 145.379 deg
 23281.20ns INFO     cocotb.dsp_core                    ********************   Open Loop Test   ********************
 23281.20ns INFO     cocotb.dsp_core                    LLRFModel TX:
                                                        < DSPCoreTX   :   Amp gain= 0.387,   Phs gain=    0.00 deg >
                                                        DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                        DUC           :   Amp gain= 0.250,   Phs gain=  172.17 deg;
                                                        CORDIC        :   Amp gain= 1.647,   Phs gain= -172.17 deg;

 26091.30ns INFO     cocotb.dsp_core                    expected mag: 22544.21 cnt,  phs: -149.561 deg
 26100.00ns INFO     cocotb.dsp_core                    measured mag: 22542.76 cnt,  phs: -149.562 deg
 26108.70ns INFO     cocotb.dsp_core                    measured mag: 22542.76 cnt,  phs: -149.562 deg
 26117.40ns INFO     cocotb.dsp_core                    measured mag: 22542.76 cnt,  phs: -149.562 deg
 26126.10ns INFO     cocotb.dsp_core                    measured mag: 22543.47 cnt,  phs: -149.562 deg
 26134.80ns INFO     cocotb.dsp_core                    measured mag: 22544.35 cnt,  phs: -149.564 deg
 26134.80ns INFO     cocotb.dsp_core                    ********************  Close Loop Test   ********************
 26134.80ns INFO     cocotb.dsp_core                    Cavity Model:
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
 43926.30ns INFO     cocotb.dsp_core                    expected mag: 20289.79 cnt,  phs: 85.227 deg
 43935.00ns INFO     cocotb.dsp_core                    measured mag: 20290.20 cnt,  phs: 85.224 deg
 43943.70ns INFO     cocotb.dsp_core                    measured mag: 20289.67 cnt,  phs: 85.225 deg
 43952.40ns INFO     cocotb.dsp_core                    measured mag: 20289.32 cnt,  phs: 85.226 deg
 43961.10ns INFO     cocotb.dsp_core                    measured mag: 20288.61 cnt,  phs: 85.226 deg
 43969.80ns INFO     cocotb.dsp_core                    measured mag: 20288.08 cnt,  phs: 85.228 deg
 43969.80ns INFO     cocotb.regression                  test_uspas passed
 43969.80ns INFO     cocotb.regression                  running test_lemp (3/4)
 43969.80ns INFO     cocotb.dsp_core                    ********************  Simulating: LEMP  ********************
 43969.80ns INFO     cocotb.dsp_core                    RX phase off:    79.46 deg; TX phase off:   128.57 deg
 43969.80ns INFO     cocotb.dsp_core                    RX phase off:   115720 cnt; TX phase off:   187245 cnt
 43969.80ns INFO     cocotb.dsp_core                    ********************      RX Test       ********************
 43969.80ns INFO     cocotb.dsp_core                    LLRFModel RX:
                                                        < DSPCoreRX   :   Amp gain= 6.228,   Phs gain=    0.00 deg >
                                                        WashoutFilter :   Amp gain= 1.031,   Phs gain=  -74.83 deg;
                                                        DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                        DDC           :   Amp gain= 3.900,   Phs gain=  154.29 deg;
                                                        CORDIC        :   Amp gain= 1.647,   Phs gain=  -79.46 deg;

 45213.59ns INFO     cocotb.dsp_core                    expected mag: 20519.38 cnt,  phs: -23.559 deg
 45222.00ns INFO     cocotb.dsp_core                    measured mag: 20514.53 cnt,  phs: -23.560 deg
 45230.40ns INFO     cocotb.dsp_core                    measured mag: 20527.53 cnt,  phs: -23.497 deg
 45238.81ns INFO     cocotb.dsp_core                    measured mag: 20523.36 cnt,  phs: -23.553 deg
 45247.21ns INFO     cocotb.dsp_core                    measured mag: 20519.34 cnt,  phs: -23.610 deg
 45255.61ns INFO     cocotb.dsp_core                    measured mag: 20515.01 cnt,  phs: -23.570 deg
 45255.61ns INFO     cocotb.dsp_core                    ********************   Open Loop Test   ********************
 45255.61ns INFO     cocotb.dsp_core                    LLRFModel TX:
                                                        < DSPCoreTX   :   Amp gain= 0.387,   Phs gain=   -0.00 deg >
                                                        DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                        DUC           :   Amp gain= 0.250,   Phs gain=  128.57 deg;
                                                        CORDIC        :   Amp gain= 1.647,   Phs gain= -128.57 deg;

 48129.78ns INFO     cocotb.dsp_core                    expected mag: 20519.38 cnt,  phs: -132.518 deg
 48138.19ns INFO     cocotb.dsp_core                    measured mag: 20520.31 cnt,  phs: -132.517 deg
 48146.59ns INFO     cocotb.dsp_core                    measured mag: 20518.70 cnt,  phs: -132.518 deg
 48154.99ns INFO     cocotb.dsp_core                    measured mag: 20517.10 cnt,  phs: -132.520 deg
 48163.40ns INFO     cocotb.dsp_core                    measured mag: 20517.90 cnt,  phs: -132.520 deg
 48171.80ns INFO     cocotb.dsp_core                    measured mag: 20518.70 cnt,  phs: -132.518 deg
 48171.80ns INFO     cocotb.dsp_core                    ********************  Close Loop Test   ********************
 48171.80ns INFO     cocotb.dsp_core                    Cavity Model:
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
 65282.35ns INFO     cocotb.dsp_core                    expected mag: 18467.44 cnt,  phs: 58.201 deg
 65290.75ns INFO     cocotb.dsp_core                    measured mag: 18467.49 cnt,  phs: 58.200 deg
 65299.15ns INFO     cocotb.dsp_core                    measured mag: 18467.81 cnt,  phs: 58.204 deg
 65307.56ns INFO     cocotb.dsp_core                    measured mag: 18468.61 cnt,  phs: 58.200 deg
 65315.96ns INFO     cocotb.dsp_core                    measured mag: 18469.26 cnt,  phs: 58.196 deg
 65324.37ns INFO     cocotb.dsp_core                    measured mag: 18467.81 cnt,  phs: 58.199 deg
 65324.37ns INFO     cocotb.regression                  test_lemp passed
 65324.37ns INFO     cocotb.regression                  running test_awa (4/4)
 65324.37ns INFO     cocotb.dsp_core                    ********************  Simulating: AWA   ********************
 65324.37ns INFO     cocotb.dsp_core                    RX phase off:    78.71 deg; TX phase off:   130.91 deg
 65324.37ns INFO     cocotb.dsp_core                    RX phase off:   114633 cnt; TX phase off:   190650 cnt
 65324.37ns INFO     cocotb.dsp_core                    ********************      RX Test       ********************
 65324.37ns INFO     cocotb.dsp_core                    LLRFModel RX:
                                                        < DSPCoreRX   :   Amp gain= 6.202,   Phs gain=   -0.00 deg >
                                                        WashoutFilter :   Amp gain= 1.031,   Phs gain=  -74.01 deg;
                                                        DDS           :   Amp gain= 0.939,   Phs gain=    0.00 deg;
                                                        DDC           :   Amp gain= 3.887,   Phs gain=  152.73 deg;
                                                        CORDIC        :   Amp gain= 1.647,   Phs gain=  -78.71 deg;

 66936.48ns INFO     cocotb.dsp_core                    expected mag: 20607.13 cnt,  phs: -158.189 deg
 66947.09ns INFO     cocotb.dsp_core                    measured mag: 20638.38 cnt,  phs: -158.180 deg
 66957.69ns INFO     cocotb.dsp_core                    measured mag: 20610.48 cnt,  phs: -158.199 deg
 66968.30ns INFO     cocotb.dsp_core                    measured mag: 20582.59 cnt,  phs: -158.217 deg
 66978.90ns INFO     cocotb.dsp_core                    measured mag: 20600.49 cnt,  phs: -158.184 deg
 66989.51ns INFO     cocotb.dsp_core                    measured mag: 20618.55 cnt,  phs: -158.151 deg
 66989.51ns INFO     cocotb.dsp_core                    ********************   Open Loop Test   ********************
 66989.51ns INFO     cocotb.dsp_core                    LLRFModel TX:
                                                        < DSPCoreTX   :   Amp gain= 0.387,   Phs gain=    0.00 deg >
                                                        DDS           :   Amp gain= 0.939,   Phs gain=    0.00 deg;
                                                        DUC           :   Amp gain= 0.250,   Phs gain=  130.91 deg;
                                                        CORDIC        :   Amp gain= 1.647,   Phs gain= -130.91 deg;

 70436.46ns INFO     cocotb.dsp_core                    expected mag: 20607.13 cnt,  phs: 157.533 deg
 70447.07ns INFO     cocotb.dsp_core                    measured mag: 20606.78 cnt,  phs: 157.526 deg
 70457.67ns INFO     cocotb.dsp_core                    measured mag: 20606.29 cnt,  phs: 157.529 deg
 70468.28ns INFO     cocotb.dsp_core                    measured mag: 20605.81 cnt,  phs: 157.532 deg
 70478.88ns INFO     cocotb.dsp_core                    measured mag: 20606.61 cnt,  phs: 157.530 deg
 70489.49ns INFO     cocotb.dsp_core                    measured mag: 20607.58 cnt,  phs: 157.530 deg
 70489.49ns INFO     cocotb.dsp_core                    ********************  Close Loop Test   ********************
 70489.49ns INFO     cocotb.dsp_core                    Cavity Model:
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
 92083.30ns INFO     cocotb.dsp_core                    expected mag: 18546.42 cnt,  phs: 112.032 deg
 92093.91ns INFO     cocotb.dsp_core                    measured mag: 18546.47 cnt,  phs: 112.030 deg
 92104.52ns INFO     cocotb.dsp_core                    measured mag: 18545.99 cnt,  phs: 112.033 deg
 92115.12ns INFO     cocotb.dsp_core                    measured mag: 18546.95 cnt,  phs: 112.033 deg
 92125.73ns INFO     cocotb.dsp_core                    measured mag: 18547.92 cnt,  phs: 112.033 deg
 92136.34ns INFO     cocotb.dsp_core                    measured mag: 18546.95 cnt,  phs: 112.032 deg
 92136.34ns INFO     cocotb.regression                  test_awa passed
 92136.34ns INFO     cocotb.regression                  **************************************************************************************
                                                        ** TEST                          STATUS  SIM TIME (ns)  REAL TIME (s)  RATIO (ns/s) **
                                                        **************************************************************************************
                                                        ** test_dsp_core.test_alsu        PASS       21941.40           0.82      26761.71  **
                                                        ** test_dsp_core.test_uspas       PASS       22028.40           0.84      26321.46  **
                                                        ** test_dsp_core.test_lemp        PASS       21354.56           1.05      20431.01  **
                                                        ** test_dsp_core.test_awa         PASS       26811.97           0.92      29047.14  **
                                                        **************************************************************************************
                                                        ** TESTS=4 PASS=4 FAIL=0 SKIP=0              92136.34           4.33      21288.93  **
                                                        **************************************************************************************
```

3. Check waveform:
   ```
   gtkwave dump.fst dump.gtkw
   ```
   Typical result:
   ![waveform](../../doc/fig/waveform_example.png)
