# RTL and Physics Co-Simulation for LLRF

## Getting started

1. Install [`cocotb`](https://docs.cocotb.org/en/stable/install.html) (tested version: 1.8.1) and ['verilator`](https://verilator.org/guide/latest/install.html) (tested version: 5.018);
   ```
   sudo apt install verilator
   pip install cocotb pytest
   ```

2. Build and run simulation:
   ```
   make
   ```

   The test bench will run 4 frequency configurations: `ALSU`, `USPAS`, `LEMP` and `AWA`. It tests receiver accuracy, open loop and close loop response correspondingly. The DSP transfer functions are modeled in `llrf_dsp.py` and integrated in the test for automated calibration. The RX and TX phase rotation introduced by latency and digital filters are compensated by phase offsets of the digital down / up conversion, so that there is no need for phase calibration in software.
   Typical verification results:

```
     0.00ns INFO     cocotb                             Seeding Python random module with 1727128131
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

  1139.70ns INFO     cocotb.dsp_core                    expected mag: 26451.53 cnt,  phs: 29.467 deg
  1148.40ns INFO     cocotb.dsp_core                    measured mag: 26452.94 cnt,  phs: 29.464 deg
  1157.10ns INFO     cocotb.dsp_core                    measured mag: 26454.18 cnt,  phs: 29.461 deg
  1165.80ns INFO     cocotb.dsp_core                    measured mag: 26455.43 cnt,  phs: 29.461 deg
  1174.50ns INFO     cocotb.dsp_core                    measured mag: 26451.49 cnt,  phs: 29.465 deg
  1183.20ns INFO     cocotb.dsp_core                    measured mag: 26447.35 cnt,  phs: 29.471 deg
  1183.20ns INFO     cocotb.dsp_core                    ********************   Open Loop Test   ********************
  1183.20ns INFO     cocotb.dsp_core                    LLRFModel TX:
                                                        < DSPCoreTX   :   Amp gain= 0.387,   Phs gain=   -0.00 deg >
                                                        DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                        DUC           :   Amp gain= 0.250,   Phs gain=  -32.73 deg;
                                                        CORDIC        :   Amp gain= 1.647,   Phs gain=   32.73 deg;

  4149.90ns INFO     cocotb.dsp_core                    expected mag: 26451.53 cnt,  phs: -19.671 deg
  4158.60ns INFO     cocotb.dsp_core                    measured mag: 26450.25 cnt,  phs: -19.670 deg
  4167.30ns INFO     cocotb.dsp_core                    measured mag: 26452.11 cnt,  phs: -19.668 deg
  4176.00ns INFO     cocotb.dsp_core                    measured mag: 26453.98 cnt,  phs: -19.667 deg
  4184.70ns INFO     cocotb.dsp_core                    measured mag: 26452.11 cnt,  phs: -19.670 deg
  4193.40ns INFO     cocotb.dsp_core                    measured mag: 26450.46 cnt,  phs: -19.672 deg
  4193.40ns INFO     cocotb.dsp_core                    ********************  Close Loop Test   ********************
 21924.00ns INFO     cocotb.dsp_core                    expected mag: 23806.38 cnt,  phs: -77.077 deg
 21932.70ns INFO     cocotb.dsp_core                    measured mag: 23806.86 cnt,  phs: -77.079 deg
 21941.40ns INFO     cocotb.dsp_core                    measured mag: 23808.10 cnt,  phs: -77.076 deg
 21950.10ns INFO     cocotb.dsp_core                    measured mag: 23806.45 cnt,  phs: -77.077 deg
 21958.80ns INFO     cocotb.dsp_core                    measured mag: 23804.79 cnt,  phs: -77.079 deg
 21967.50ns INFO     cocotb.dsp_core                    measured mag: 23804.58 cnt,  phs: -77.081 deg
 21967.50ns INFO     cocotb.regression                  test_alsu passed
 21967.50ns INFO     cocotb.regression                  running test_uspas (2/4)
 21967.50ns INFO     cocotb.dsp_core                    ******************** Simulating: USPAS  ********************
 21967.50ns INFO     cocotb.dsp_core                    RX phase off:    65.65 deg; TX phase off:   172.17 deg
 21967.50ns INFO     cocotb.dsp_core                    RX phase off:    95602 cnt; TX phase off:   250746 cnt
 21967.50ns INFO     cocotb.dsp_core                    ********************      RX Test       ********************
 21967.50ns INFO     cocotb.dsp_core                    LLRFModel RX:
                                                        < DSPCoreRX   :   Amp gain= 5.669,   Phs gain=    0.00 deg >
                                                        WashoutFilter :   Amp gain= 1.031,   Phs gain=  -59.57 deg;
                                                        DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                        DDC           :   Amp gain= 3.552,   Phs gain=  125.22 deg;
                                                        CORDIC        :   Amp gain= 1.647,   Phs gain=  -65.65 deg;

 23176.80ns INFO     cocotb.dsp_core                    expected mag: 22544.21 cnt,  phs: -69.201 deg
 23185.50ns INFO     cocotb.dsp_core                    measured mag: 22539.94 cnt,  phs: -69.206 deg
 23194.20ns INFO     cocotb.dsp_core                    measured mag: 22541.35 cnt,  phs: -69.156 deg
 23202.90ns INFO     cocotb.dsp_core                    measured mag: 22545.76 cnt,  phs: -69.181 deg
 23211.60ns INFO     cocotb.dsp_core                    measured mag: 22550.00 cnt,  phs: -69.206 deg
 23220.30ns INFO     cocotb.dsp_core                    measured mag: 22545.23 cnt,  phs: -69.219 deg
 23220.30ns INFO     cocotb.dsp_core                    ********************   Open Loop Test   ********************
 23220.30ns INFO     cocotb.dsp_core                    LLRFModel TX:
                                                        < DSPCoreTX   :   Amp gain= 0.387,   Phs gain=   -0.00 deg >
                                                        DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                        DUC           :   Amp gain= 0.250,   Phs gain=  172.17 deg;
                                                        CORDIC        :   Amp gain= 1.647,   Phs gain= -172.17 deg;

 26143.50ns INFO     cocotb.dsp_core                    expected mag: 22544.21 cnt,  phs: -38.137 deg
 26152.20ns INFO     cocotb.dsp_core                    measured mag: 22544.00 cnt,  phs: -38.135 deg
 26160.90ns INFO     cocotb.dsp_core                    measured mag: 22544.53 cnt,  phs: -38.136 deg
 26169.60ns INFO     cocotb.dsp_core                    measured mag: 22544.88 cnt,  phs: -38.138 deg
 26178.30ns INFO     cocotb.dsp_core                    measured mag: 22544.17 cnt,  phs: -38.139 deg
 26187.00ns INFO     cocotb.dsp_core                    measured mag: 22543.29 cnt,  phs: -38.140 deg
 26187.00ns INFO     cocotb.dsp_core                    ********************  Close Loop Test   ********************
 43935.00ns INFO     cocotb.dsp_core                    expected mag: 20289.79 cnt,  phs: -0.045 deg
 43943.70ns INFO     cocotb.dsp_core                    measured mag: 20289.84 cnt,  phs: -0.044 deg
 43952.40ns INFO     cocotb.dsp_core                    measured mag: 20291.26 cnt,  phs: -0.043 deg
 43961.10ns INFO     cocotb.dsp_core                    measured mag: 20290.02 cnt,  phs: -0.045 deg
 43969.80ns INFO     cocotb.dsp_core                    measured mag: 20288.79 cnt,  phs: -0.047 deg
 43978.50ns INFO     cocotb.dsp_core                    measured mag: 20289.84 cnt,  phs: -0.047 deg
 43978.50ns INFO     cocotb.regression                  test_uspas passed
 43978.50ns INFO     cocotb.regression                  running test_lemp (3/4)
 43978.50ns INFO     cocotb.dsp_core                    ********************  Simulating: LEMP  ********************
 43978.50ns INFO     cocotb.dsp_core                    RX phase off:    79.46 deg; TX phase off:   128.57 deg
 43978.50ns INFO     cocotb.dsp_core                    RX phase off:   115720 cnt; TX phase off:   187245 cnt
 43978.50ns INFO     cocotb.dsp_core                    ********************      RX Test       ********************
 43978.50ns INFO     cocotb.dsp_core                    LLRFModel RX:
                                                        < DSPCoreRX   :   Amp gain= 6.228,   Phs gain=   -0.00 deg >
                                                        WashoutFilter :   Amp gain= 1.031,   Phs gain=  -74.83 deg;
                                                        DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                        DDC           :   Amp gain= 3.900,   Phs gain=  154.29 deg;
                                                        CORDIC        :   Amp gain= 1.647,   Phs gain=  -79.46 deg;

 45113.04ns INFO     cocotb.dsp_core                    expected mag: 20519.38 cnt,  phs: 46.581 deg
 45121.45ns INFO     cocotb.dsp_core                    measured mag: 20518.54 cnt,  phs: 46.578 deg
 45129.85ns INFO     cocotb.dsp_core                    measured mag: 20515.97 cnt,  phs: 46.579 deg
 45138.25ns INFO     cocotb.dsp_core                    measured mag: 20517.74 cnt,  phs: 46.581 deg
 45146.66ns INFO     cocotb.dsp_core                    measured mag: 20519.67 cnt,  phs: 46.582 deg
 45155.06ns INFO     cocotb.dsp_core                    measured mag: 20518.70 cnt,  phs: 46.579 deg
 45155.06ns INFO     cocotb.dsp_core                    ********************   Open Loop Test   ********************
 45155.06ns INFO     cocotb.dsp_core                    LLRFModel TX:
                                                        < DSPCoreTX   :   Amp gain= 0.387,   Phs gain=   -0.00 deg >
                                                        DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                        DUC           :   Amp gain= 0.250,   Phs gain=  128.57 deg;
                                                        CORDIC        :   Amp gain= 1.647,   Phs gain= -128.57 deg;

 47970.40ns INFO     cocotb.dsp_core                    expected mag: 20519.38 cnt,  phs: 176.534 deg
 47978.81ns INFO     cocotb.dsp_core                    measured mag: 20519.18 cnt,  phs: 176.532 deg
 47987.21ns INFO     cocotb.dsp_core                    measured mag: 20519.99 cnt,  phs: 176.530 deg
 47995.61ns INFO     cocotb.dsp_core                    measured mag: 20519.02 cnt,  phs: 176.531 deg
 48004.02ns INFO     cocotb.dsp_core                    measured mag: 20518.06 cnt,  phs: 176.534 deg
 48012.42ns INFO     cocotb.dsp_core                    measured mag: 20518.86 cnt,  phs: 176.534 deg
 48012.42ns INFO     cocotb.dsp_core                    ********************  Close Loop Test   ********************
 65139.77ns INFO     cocotb.dsp_core                    expected mag: 18467.44 cnt,  phs: -23.557 deg
 65148.18ns INFO     cocotb.dsp_core                    measured mag: 18467.81 cnt,  phs: -23.559 deg
 65156.58ns INFO     cocotb.dsp_core                    measured mag: 18467.97 cnt,  phs: -23.556 deg
 65164.99ns INFO     cocotb.dsp_core                    measured mag: 18467.97 cnt,  phs: -23.553 deg
 65173.39ns INFO     cocotb.dsp_core                    measured mag: 18468.29 cnt,  phs: -23.553 deg
 65181.79ns INFO     cocotb.dsp_core                    measured mag: 18468.45 cnt,  phs: -23.553 deg
 65181.79ns INFO     cocotb.regression                  test_lemp passed
 65181.79ns INFO     cocotb.regression                  running test_awa (4/4)
 65181.79ns INFO     cocotb.dsp_core                    ********************  Simulating: AWA   ********************
 65181.79ns INFO     cocotb.dsp_core                    RX phase off:    78.71 deg; TX phase off:   130.91 deg
 65181.79ns INFO     cocotb.dsp_core                    RX phase off:   114633 cnt; TX phase off:   190650 cnt
 65181.79ns INFO     cocotb.dsp_core                    ********************      RX Test       ********************
 65181.79ns INFO     cocotb.dsp_core                    LLRFModel RX:
                                                        < DSPCoreRX   :   Amp gain= 6.202,   Phs gain=   -0.00 deg >
                                                        WashoutFilter :   Amp gain= 1.031,   Phs gain=  -74.01 deg;
                                                        DDS           :   Amp gain= 0.939,   Phs gain=    0.00 deg;
                                                        DDC           :   Amp gain= 3.887,   Phs gain=  152.73 deg;
                                                        CORDIC        :   Amp gain= 1.647,   Phs gain=  -78.71 deg;

 66698.45ns INFO     cocotb.dsp_core                    expected mag: 20607.13 cnt,  phs: 170.370 deg
 66709.06ns INFO     cocotb.dsp_core                    measured mag: 20611.61 cnt,  phs: 170.379 deg
 66719.66ns INFO     cocotb.dsp_core                    measured mag: 20606.94 cnt,  phs: 170.368 deg
 66730.27ns INFO     cocotb.dsp_core                    measured mag: 20602.42 cnt,  phs: 170.355 deg
 66740.88ns INFO     cocotb.dsp_core                    measured mag: 20604.84 cnt,  phs: 170.370 deg
 66751.48ns INFO     cocotb.dsp_core                    measured mag: 20607.42 cnt,  phs: 170.384 deg
 66751.48ns INFO     cocotb.dsp_core                    ********************   Open Loop Test   ********************
 66751.48ns INFO     cocotb.dsp_core                    LLRFModel TX:
                                                        < DSPCoreTX   :   Amp gain= 0.387,   Phs gain=    0.00 deg >
                                                        DDS           :   Amp gain= 0.939,   Phs gain=    0.00 deg;
                                                        DUC           :   Amp gain= 0.250,   Phs gain=  130.91 deg;
                                                        CORDIC        :   Amp gain= 1.647,   Phs gain= -130.91 deg;

 70325.71ns INFO     cocotb.dsp_core                    expected mag: 20607.13 cnt,  phs: -147.918 deg
 70336.31ns INFO     cocotb.dsp_core                    measured mag: 20606.78 cnt,  phs: -147.920 deg
 70346.92ns INFO     cocotb.dsp_core                    measured mag: 20606.61 cnt,  phs: -147.917 deg
 70357.52ns INFO     cocotb.dsp_core                    measured mag: 20606.29 cnt,  phs: -147.916 deg
 70368.13ns INFO     cocotb.dsp_core                    measured mag: 20606.78 cnt,  phs: -147.919 deg
 70378.74ns INFO     cocotb.dsp_core                    measured mag: 20607.10 cnt,  phs: -147.921 deg
 70378.74ns INFO     cocotb.dsp_core                    ********************  Close Loop Test   ********************
 92025.58ns INFO     cocotb.dsp_core                    expected mag: 18546.42 cnt,  phs: 49.252 deg
 92036.19ns INFO     cocotb.dsp_core                    measured mag: 18547.76 cnt,  phs: 49.243 deg
 92046.79ns INFO     cocotb.dsp_core                    measured mag: 18546.15 cnt,  phs: 49.249 deg
 92057.40ns INFO     cocotb.dsp_core                    measured mag: 18544.53 cnt,  phs: 49.254 deg
 92068.01ns INFO     cocotb.dsp_core                    measured mag: 18545.82 cnt,  phs: 49.252 deg
 92078.61ns INFO     cocotb.dsp_core                    measured mag: 18547.28 cnt,  phs: 49.250 deg
 92078.61ns INFO     cocotb.regression                  test_awa passed
 92078.61ns INFO     cocotb.regression                  **************************************************************************************
                                                        ** TEST                          STATUS  SIM TIME (ns)  REAL TIME (s)  RATIO (ns/s) **
                                                        **************************************************************************************
                                                        ** test_dsp_core.test_alsu        PASS       21967.50           5.14       4274.20  **
                                                        ** test_dsp_core.test_uspas       PASS       22011.00           5.11       4310.64  **
                                                        ** test_dsp_core.test_lemp        PASS       21203.29           4.99       4245.63  **
                                                        ** test_dsp_core.test_awa         PASS       26896.82           4.52       5950.93  **
                                                        **************************************************************************************
                                                        ** TESTS=4 PASS=4 FAIL=0 SKIP=0              92078.61          20.00       4602.95  **
                                                        **************************************************************************************
```

3. Check waveform:
   ```
   gtkwave dump.fst dump.gtkw
   ```
   Typical result:
   ![waveform](../../doc/fig/waveform_example.png)
