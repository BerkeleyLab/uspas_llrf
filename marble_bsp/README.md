# Waveform trigger logic

Firmware supports three trigger optionsi (falling edge), internal, external trigger, and delayed external trigger using register `wave_trig_sel`.\
External trigger can be either from top row Pmod J18 pins on Zest next to ground pin or top row of Pmod J12 pins on Marble. \
Module `etrig_bridge.v` is used to select between the two Pmods and individual pins can be selected based in register `etrig_pmod_sel`.

## Example:
Zest Pmod J18 (DE9 connector) for AWA usecase. Connect an external trigger to the RS232 (pin 6 DSR and pin 5 GND) on the back panel of LCLS-II style 3U chassis and set the following registers. Monitor the trigger counter register etrig_pulse_cnt to cross check.

```
python3 -m leep.cli leep://$IP:803 reg wave_trig_sel=1 etrig_sel=2
```

Pmod J12 on Marble: Connect an external trigger to the any of the first four pins on J12 and set the following registers. Again, monitor the trigger counter register etrig_pulse_cnt to cross check. Here $pmod_pin is either 0, 1, 2 or 3 which corresponds to the four pins.

```
python3 -m leep.cli leep://$IP:803 reg wave_trig_sel=1 etrig_sel=1 etrig_pmod_sel=$pmod_pin
```
