* List available registers

    python test.py [leep://192.168.19.122:803] list

* Read register

    python test.py [leep://192.168.19.122:803] reg chan_keep

* Write register

    python test.py [leep://192.168.19.122:803] reg chak_keep=0x3ff

* Plot ADC waveforms

    python test.py [leep://192.168.19.122:803] waveform -p
