# RTL and Physics Co-Simulation for LLRF

## Getting started

1. Install [`cocotb`](https://docs.cocotb.org/en/stable/install.html) (tested version: 1.9.2) and ['verilator`](https://verilator.org/guide/latest/install.html) (tested version: 5.038);

   ```bash
   sudo apt install verilator
   pip install cocotb==1.9.2 pytest
   ```

2. Build and run simulation:

   ```bash
   make
   ```

   The test bench will run 4 frequency configurations: `ALSU`, `USPAS`, `LEMP` and `AWA`. It tests receiver accuracy, open loop and close loop response correspondingly. The DSP transfer functions are modeled in `llrf_dsp.py` and integrated in the test for automated calibration. The RX and TX phase rotation introduced by latency and digital filters are compensated by phase offsets of the digital down / up conversion, so that there is no need for phase calibration in software.
   Typical verification results:

   ```bash
      0.00ns INFO     cocotb                             Seeding Python random module with 1755063140
      0.00ns INFO     cocotb.regression                  Found test test_llrf_dsp.test_alsu
      0.00ns INFO     cocotb.regression                  Found test test_llrf_dsp.test_uspas
      0.00ns INFO     cocotb.regression                  Found test test_llrf_dsp.test_lemp
      0.00ns INFO     cocotb.regression                  Found test test_llrf_dsp.test_awa
      0.00ns INFO     cocotb.regression                  running test_alsu (1/4)
      0.00ns INFO     cocotb.llrf_dsp                    ********************  Simulating: ALSU  ********************
      0.00ns INFO     cocotb.llrf_dsp                    LLRFModel:
                                                         < LLRFModel   :   Amp gain= 3.740,   Phs gain=    0.00 deg >
                                                         WashoutFilter :   Amp gain= 1.032,   Phs gain= -130.07 deg;
                                                         DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                         DDC           :   Amp gain= 1.511,   Phs gain=  -98.18 deg;
                                                         CORDIC        :   Amp gain= 1.647,   Phs gain= -131.75 deg;
                                                         DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                         DUC           :   Amp gain= 1.000,   Phs gain=  -32.73 deg;
                                                         CORDIC        :   Amp gain= 1.647,   Phs gain=   32.73 deg;

      0.00ns INFO     cocotb.llrf_dsp                    RX phase off:   131.75 deg; TX phase off:   -32.73 deg
      0.00ns INFO     cocotb.llrf_dsp                    inlk_gain:   0.285443
      0.00ns INFO     cocotb.llrf_dsp                    mon_gain:    5.546751
      0.00ns INFO     cocotb.llrf_dsp                    ********************      RX Test       ********************
      0.00ns INFO     cocotb.llrf_dsp                    LLRFModel RX:
                                                         < DSPCoreRX   :   Amp gain= 2.416,   Phs gain=    0.00 deg >
                                                         WashoutFilter :   Amp gain= 1.032,   Phs gain= -130.07 deg;
                                                         DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                         DDC           :   Amp gain= 1.511,   Phs gain=  -98.18 deg;
                                                         CORDIC        :   Amp gain= 1.647,   Phs gain= -131.75 deg;

   1887.90ns WARNING  cocotb.llrf_dsp                    expected mag: 31129.60 cnt,  phs: 168.202 deg
   1896.60ns WARNING  cocotb.llrf_dsp                    measured mag: 31127.88 cnt,  phs: 168.199 deg
   1905.30ns WARNING  cocotb.llrf_dsp                    measured mag: 31126.64 cnt,  phs: 168.198 deg
   1914.00ns WARNING  cocotb.llrf_dsp                    measured mag: 31128.29 cnt,  phs: 168.201 deg
   1922.70ns WARNING  cocotb.llrf_dsp                    measured mag: 31129.95 cnt,  phs: 168.203 deg
   1931.40ns WARNING  cocotb.llrf_dsp                    measured mag: 31130.36 cnt,  phs: 168.205 deg
   1931.40ns INFO     cocotb.llrf_dsp                    ********************   Open Loop Test   ********************
   1931.40ns INFO     cocotb.llrf_dsp                    LLRFModel TX:
                                                         < DSPCoreTX   :   Amp gain= 1.548,   Phs gain=    0.00 deg >
                                                         DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                         DUC           :   Amp gain= 1.000,   Phs gain=  -32.73 deg;
                                                         CORDIC        :   Amp gain= 1.647,   Phs gain=   32.73 deg;

   4828.50ns WARNING  cocotb.llrf_dsp                    expected mag: 31129.60 cnt,  phs: 88.765 deg
   4837.20ns WARNING  cocotb.llrf_dsp                    measured mag: 31129.12 cnt,  phs: 88.761 deg
   4845.90ns WARNING  cocotb.llrf_dsp                    measured mag: 31128.71 cnt,  phs: 88.767 deg
   4854.60ns WARNING  cocotb.llrf_dsp                    measured mag: 31128.29 cnt,  phs: 88.768 deg
   4863.30ns WARNING  cocotb.llrf_dsp                    measured mag: 31127.88 cnt,  phs: 88.768 deg
   4872.00ns WARNING  cocotb.llrf_dsp                    measured mag: 31128.71 cnt,  phs: 88.764 deg
   4872.00ns INFO     cocotb.llrf_dsp                    ********************  Close Loop Test   ********************
   4872.00ns INFO     cocotb.llrf_dsp                    Cavity Model:
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
   22663.50ns WARNING  cocotb.llrf_dsp                    expected mag: 28016.64 cnt,  phs: -151.973 deg
   22672.20ns WARNING  cocotb.llrf_dsp                    measured mag: 28015.26 cnt,  phs: -151.968 deg
   22680.90ns WARNING  cocotb.llrf_dsp                    measured mag: 28014.84 cnt,  phs: -151.967 deg
   22689.60ns WARNING  cocotb.llrf_dsp                    measured mag: 28016.08 cnt,  phs: -151.970 deg
   22698.30ns WARNING  cocotb.llrf_dsp                    measured mag: 28016.91 cnt,  phs: -151.973 deg
   22707.00ns WARNING  cocotb.llrf_dsp                    measured mag: 28017.74 cnt,  phs: -151.971 deg
   22707.00ns INFO     cocotb.regression                  test_alsu passed
   22707.00ns INFO     cocotb.regression                  running test_uspas (2/4)
   22707.00ns INFO     cocotb.llrf_dsp                    ******************** Simulating: USPAS  ********************
   22707.00ns INFO     cocotb.llrf_dsp                    LLRFModel:
                                                         < LLRFModel   :   Amp gain= 4.389,   Phs gain=   -0.00 deg >
                                                         WashoutFilter :   Amp gain= 1.031,   Phs gain=  -59.57 deg;
                                                         DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                         DDC           :   Amp gain= 1.776,   Phs gain=  125.22 deg;
                                                         CORDIC        :   Amp gain= 1.647,   Phs gain=  -65.65 deg;
                                                         DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                         DUC           :   Amp gain= 1.000,   Phs gain=  172.17 deg;
                                                         CORDIC        :   Amp gain= 1.647,   Phs gain= -172.17 deg;

   22707.00ns INFO     cocotb.llrf_dsp                    RX phase off:    65.65 deg; TX phase off:   172.17 deg
   22707.00ns INFO     cocotb.llrf_dsp                    inlk_gain:   0.366054
   22707.00ns INFO     cocotb.llrf_dsp                    mon_gain:    7.113198
   22707.00ns INFO     cocotb.llrf_dsp                    ********************      RX Test       ********************
   22707.00ns INFO     cocotb.llrf_dsp                    LLRFModel RX:
                                                         < DSPCoreRX   :   Amp gain= 2.834,   Phs gain=    0.00 deg >
                                                         WashoutFilter :   Amp gain= 1.031,   Phs gain=  -59.57 deg;
                                                         DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                         DDC           :   Amp gain= 1.776,   Phs gain=  125.22 deg;
                                                         CORDIC        :   Amp gain= 1.647,   Phs gain=  -65.65 deg;

   24594.90ns WARNING  cocotb.llrf_dsp                    expected mag: 31129.60 cnt,  phs: -116.165 deg
   24603.60ns WARNING  cocotb.llrf_dsp                    measured mag: 31129.47 cnt,  phs: -116.163 deg
   24612.30ns WARNING  cocotb.llrf_dsp                    measured mag: 31129.11 cnt,  phs: -116.161 deg
   24621.00ns WARNING  cocotb.llrf_dsp                    measured mag: 31129.47 cnt,  phs: -116.164 deg
   24629.70ns WARNING  cocotb.llrf_dsp                    measured mag: 31129.47 cnt,  phs: -116.168 deg
   24638.40ns WARNING  cocotb.llrf_dsp                    measured mag: 31129.47 cnt,  phs: -116.165 deg
   24638.40ns INFO     cocotb.llrf_dsp                    ********************   Open Loop Test   ********************
   24638.40ns INFO     cocotb.llrf_dsp                    LLRFModel TX:
                                                         < DSPCoreTX   :   Amp gain= 1.548,   Phs gain=   -0.00 deg >
                                                         DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                         DUC           :   Amp gain= 1.000,   Phs gain=  172.17 deg;
                                                         CORDIC        :   Amp gain= 1.647,   Phs gain= -172.17 deg;

   27596.40ns WARNING  cocotb.llrf_dsp                    expected mag: 31129.60 cnt,  phs: 137.437 deg
   27605.10ns WARNING  cocotb.llrf_dsp                    measured mag: 31130.17 cnt,  phs: 137.438 deg
   27613.80ns WARNING  cocotb.llrf_dsp                    measured mag: 31129.82 cnt,  phs: 137.436 deg
   27622.50ns WARNING  cocotb.llrf_dsp                    measured mag: 31129.47 cnt,  phs: 137.435 deg
   27631.20ns WARNING  cocotb.llrf_dsp                    measured mag: 31130.17 cnt,  phs: 137.438 deg
   27639.90ns WARNING  cocotb.llrf_dsp                    measured mag: 31130.52 cnt,  phs: 137.439 deg
   27639.90ns INFO     cocotb.llrf_dsp                    ********************  Close Loop Test   ********************
   27639.90ns INFO     cocotb.llrf_dsp                    Cavity Model:
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
   45431.40ns WARNING  cocotb.llrf_dsp                    expected mag: 28016.64 cnt,  phs: 125.810 deg
   45440.10ns WARNING  cocotb.llrf_dsp                    measured mag: 28013.73 cnt,  phs: 125.809 deg
   45448.80ns WARNING  cocotb.llrf_dsp                    measured mag: 28014.44 cnt,  phs: 125.807 deg
   45457.50ns WARNING  cocotb.llrf_dsp                    measured mag: 28015.14 cnt,  phs: 125.807 deg
   45466.20ns WARNING  cocotb.llrf_dsp                    measured mag: 28015.14 cnt,  phs: 125.810 deg
   45474.90ns WARNING  cocotb.llrf_dsp                    measured mag: 28015.50 cnt,  phs: 125.813 deg
   45474.90ns INFO     cocotb.regression                  test_uspas passed
   45474.90ns INFO     cocotb.regression                  running test_lemp (3/4)
   45474.90ns INFO     cocotb.llrf_dsp                    ********************  Simulating: LEMP  ********************
   45474.90ns INFO     cocotb.llrf_dsp                    LLRFModel:
                                                         < LLRFModel   :   Amp gain= 4.822,   Phs gain=   -0.00 deg >
                                                         WashoutFilter :   Amp gain= 1.031,   Phs gain=  -74.83 deg;
                                                         DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                         DDC           :   Amp gain= 1.950,   Phs gain=  154.29 deg;
                                                         CORDIC        :   Amp gain= 1.647,   Phs gain=  -79.46 deg;
                                                         DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                         DUC           :   Amp gain= 1.000,   Phs gain=  128.57 deg;
                                                         CORDIC        :   Amp gain= 1.647,   Phs gain= -128.57 deg;

   45474.90ns INFO     cocotb.llrf_dsp                    RX phase off:    79.46 deg; TX phase off:   128.57 deg
   45474.90ns INFO     cocotb.llrf_dsp                    inlk_gain:   0.596041
   45474.90ns INFO     cocotb.llrf_dsp                    mon_gain:   11.582334
   45474.90ns INFO     cocotb.llrf_dsp                    ********************      RX Test       ********************
   45474.90ns INFO     cocotb.llrf_dsp                    LLRFModel RX:
                                                         < DSPCoreRX   :   Amp gain= 3.114,   Phs gain=   -0.00 deg >
                                                         WashoutFilter :   Amp gain= 1.031,   Phs gain=  -74.83 deg;
                                                         DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                         DDC           :   Amp gain= 1.950,   Phs gain=  154.29 deg;
                                                         CORDIC        :   Amp gain= 1.647,   Phs gain=  -79.46 deg;

   47297.70ns WARNING  cocotb.llrf_dsp                    expected mag: 31129.60 cnt,  phs: -116.732 deg
   47306.10ns WARNING  cocotb.llrf_dsp                    measured mag: 31130.25 cnt,  phs: -116.731 deg
   47314.50ns WARNING  cocotb.llrf_dsp                    measured mag: 31129.29 cnt,  phs: -116.731 deg
   47322.90ns WARNING  cocotb.llrf_dsp                    measured mag: 31128.65 cnt,  phs: -116.731 deg
   47331.30ns WARNING  cocotb.llrf_dsp                    measured mag: 31128.97 cnt,  phs: -116.731 deg
   47339.70ns WARNING  cocotb.llrf_dsp                    measured mag: 31129.29 cnt,  phs: -116.732 deg
   47339.70ns INFO     cocotb.llrf_dsp                    ********************   Open Loop Test   ********************
   47339.70ns INFO     cocotb.llrf_dsp                    LLRFModel TX:
                                                         < DSPCoreTX   :   Amp gain= 1.548,   Phs gain=   -0.00 deg >
                                                         DDS           :   Amp gain= 0.940,   Phs gain=    0.00 deg;
                                                         DUC           :   Amp gain= 1.000,   Phs gain=  128.57 deg;
                                                         CORDIC        :   Amp gain= 1.647,   Phs gain= -128.57 deg;

   50145.30ns WARNING  cocotb.llrf_dsp                    expected mag: 31129.60 cnt,  phs: 44.884 deg
   50153.70ns WARNING  cocotb.llrf_dsp                    measured mag: 31128.97 cnt,  phs: 44.885 deg
   50162.10ns WARNING  cocotb.llrf_dsp                    measured mag: 31127.68 cnt,  phs: 44.886 deg
   50170.50ns WARNING  cocotb.llrf_dsp                    measured mag: 31128.97 cnt,  phs: 44.883 deg
   50178.90ns WARNING  cocotb.llrf_dsp                    measured mag: 31130.25 cnt,  phs: 44.882 deg
   50187.30ns WARNING  cocotb.llrf_dsp                    measured mag: 31129.61 cnt,  phs: 44.885 deg
   50187.30ns INFO     cocotb.llrf_dsp                    ********************  Close Loop Test   ********************
   50187.30ns INFO     cocotb.llrf_dsp                    Cavity Model:
                                                         Config:            LEMP
                                                         Q_L:             1818.2
                                                         Center freq:     2856.0 MHz
                                                         half bandwidth:   785.4 kHz
                                                         F_if:              25.5 MHz
                                                         F_adc:            119.0 MHz
                                                         system_z:      TransferFunctionDiscrete(
                                                         array([ 0.03980252,  0.        , -0.03980252]),
                                                         array([ 1.        , -0.42732808,  0.92039495]),
                                                         dt: 8.4e-09
                                                         )
   67289.70ns WARNING  cocotb.llrf_dsp                    expected mag: 28016.64 cnt,  phs: -134.461 deg
   67298.10ns WARNING  cocotb.llrf_dsp                    measured mag: 28016.26 cnt,  phs: -134.460 deg
   67306.50ns WARNING  cocotb.llrf_dsp                    measured mag: 28017.23 cnt,  phs: -134.459 deg
   67314.90ns WARNING  cocotb.llrf_dsp                    measured mag: 28018.19 cnt,  phs: -134.458 deg
   67323.30ns WARNING  cocotb.llrf_dsp                    measured mag: 28016.91 cnt,  phs: -134.459 deg
   67331.70ns WARNING  cocotb.llrf_dsp                    measured mag: 28015.30 cnt,  phs: -134.459 deg
   67331.70ns INFO     cocotb.regression                  test_lemp passed
   67331.70ns INFO     cocotb.regression                  running test_awa (4/4)
   67331.70ns INFO     cocotb.llrf_dsp                    ********************  Simulating: AWA   ********************
   67331.70ns INFO     cocotb.llrf_dsp                    LLRFModel:
                                                         < LLRFModel   :   Amp gain= 4.796,   Phs gain=    0.00 deg >
                                                         WashoutFilter :   Amp gain= 1.031,   Phs gain=  -74.01 deg;
                                                         DDS           :   Amp gain= 0.939,   Phs gain=    0.00 deg;
                                                         DDC           :   Amp gain= 1.944,   Phs gain=  152.73 deg;
                                                         CORDIC        :   Amp gain= 1.647,   Phs gain=  -78.71 deg;
                                                         DDS           :   Amp gain= 0.939,   Phs gain=    0.00 deg;
                                                         DUC           :   Amp gain= 1.000,   Phs gain=  130.91 deg;
                                                         CORDIC        :   Amp gain= 1.647,   Phs gain= -130.91 deg;

   67331.70ns INFO     cocotb.llrf_dsp                    RX phase off:    78.71 deg; TX phase off:   130.91 deg
   67331.70ns INFO     cocotb.llrf_dsp                    inlk_gain:   0.824394
   67331.70ns INFO     cocotb.llrf_dsp                    mon_gain:    8.009853
   67331.70ns INFO     cocotb.llrf_dsp                    ********************      RX Test       ********************
   67331.70ns INFO     cocotb.llrf_dsp                    LLRFModel RX:
                                                         < DSPCoreRX   :   Amp gain= 3.101,   Phs gain=   -0.00 deg >
                                                         WashoutFilter :   Amp gain= 1.031,   Phs gain=  -74.01 deg;
                                                         DDS           :   Amp gain= 0.939,   Phs gain=    0.00 deg;
                                                         DDC           :   Amp gain= 1.944,   Phs gain=  152.73 deg;
                                                         CORDIC        :   Amp gain= 1.647,   Phs gain=  -78.71 deg;

   69483.50ns WARNING  cocotb.llrf_dsp                    expected mag: 31129.60 cnt,  phs: 136.449 deg
   69494.10ns WARNING  cocotb.llrf_dsp                    measured mag: 31130.84 cnt,  phs: 136.447 deg
   69504.70ns WARNING  cocotb.llrf_dsp                    measured mag: 31129.22 cnt,  phs: 136.449 deg
   69515.30ns WARNING  cocotb.llrf_dsp                    measured mag: 31127.61 cnt,  phs: 136.450 deg
   69525.90ns WARNING  cocotb.llrf_dsp                    measured mag: 31128.90 cnt,  phs: 136.447 deg
   69536.50ns WARNING  cocotb.llrf_dsp                    measured mag: 31130.19 cnt,  phs: 136.446 deg
   69536.50ns INFO     cocotb.llrf_dsp                    ********************   Open Loop Test   ********************
   69536.50ns INFO     cocotb.llrf_dsp                    LLRFModel TX:
                                                         < DSPCoreTX   :   Amp gain= 1.547,   Phs gain=    0.00 deg >
                                                         DDS           :   Amp gain= 0.939,   Phs gain=    0.00 deg;
                                                         DUC           :   Amp gain= 1.000,   Phs gain=  130.91 deg;
                                                         CORDIC        :   Amp gain= 1.647,   Phs gain= -130.91 deg;

   73076.90ns WARNING  cocotb.llrf_dsp                    expected mag: 31129.60 cnt,  phs: -11.318 deg
   73087.50ns WARNING  cocotb.llrf_dsp                    measured mag: 31130.19 cnt,  phs: -11.316 deg
   73098.10ns WARNING  cocotb.llrf_dsp                    measured mag: 31131.48 cnt,  phs: -11.316 deg
   73108.70ns WARNING  cocotb.llrf_dsp                    measured mag: 31130.19 cnt,  phs: -11.315 deg
   73119.30ns WARNING  cocotb.llrf_dsp                    measured mag: 31128.90 cnt,  phs: -11.315 deg
   73129.90ns WARNING  cocotb.llrf_dsp                    measured mag: 31129.22 cnt,  phs: -11.316 deg
   73129.90ns INFO     cocotb.llrf_dsp                    ********************  Close Loop Test   ********************
   73129.90ns INFO     cocotb.llrf_dsp                    Cavity Model:
                                                         Config:             AWA
                                                         Q_L:            10666.7
                                                         Center freq:     1300.0 MHz
                                                         half bandwidth:    60.9 kHz
                                                         F_if:              20.0 MHz
                                                         F_adc:             94.3 MHz
                                                         system_z:      TransferFunctionDiscrete(
                                                         array([ 0.00404214,  0.        , -0.00404214]),
                                                         array([ 1.        , -0.46961193,  0.99191572]),
                                                         dt: 1.0599999999999999e-08
                                                         )
   94806.90ns WARNING  cocotb.llrf_dsp                    expected mag: 28016.64 cnt,  phs: 42.390 deg
   94817.50ns WARNING  cocotb.llrf_dsp                    measured mag: 28018.69 cnt,  phs: 42.387 deg
   94828.10ns WARNING  cocotb.llrf_dsp                    measured mag: 28019.66 cnt,  phs: 42.388 deg
   94838.70ns WARNING  cocotb.llrf_dsp                    measured mag: 28018.04 cnt,  phs: 42.387 deg
   94849.30ns WARNING  cocotb.llrf_dsp                    measured mag: 28016.75 cnt,  phs: 42.387 deg
   94859.90ns WARNING  cocotb.llrf_dsp                    measured mag: 28018.04 cnt,  phs: 42.387 deg
   94859.90ns INFO     cocotb.regression                  test_awa passed
   94859.90ns INFO     cocotb.regression                  **************************************************************************************
                                                         ** TEST                          STATUS  SIM TIME (ns)  REAL TIME (s)  RATIO (ns/s) **
                                                         **************************************************************************************
                                                         ** test_llrf_dsp.test_alsu        PASS       22707.00           0.74      30818.81  **
                                                         ** test_llrf_dsp.test_uspas       PASS       22767.90           0.74      30724.78  **
                                                         ** test_llrf_dsp.test_lemp        PASS       21856.80           0.71      30765.07  **
                                                         ** test_llrf_dsp.test_awa         PASS       27528.20           0.81      34166.94  **
                                                         **************************************************************************************
                                                         ** TESTS=4 PASS=4 FAIL=0 SKIP=0              94859.90           3.74      25368.92  **
                                                         **************************************************************************************
   ```

3. Check waveform:

   ```bash
   gtkwave dump.fst dump.gtkw
   ```

   Typical result:
   ![waveform](../../doc/fig/waveform_example.png)
