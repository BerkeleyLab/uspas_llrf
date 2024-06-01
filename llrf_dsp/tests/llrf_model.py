import numpy as np
from llrf_dsp import LLRFModule, DDS, DSPCoreRX, DSPCoreTX
import json


class LLRFModel(LLRFModule):
    def __init__(self, conf='LEMP', settings_fname='../settings.json') -> None:
        """Math model that provides helper functions for simulation

        Args:
            conf (str): Application configuration key (aka FSET),
              in ['LEMP', 'ALSU', 'USPAS']
            settings_fname (str): configuration json file path
        """
        with open(settings_fname) as f:
            configs = json.load(f)
        for k, v in configs[conf].items():
            setattr(self, k, v)
        super().__init__(self.NUM_DDS, self.DEN_DDS)
        assert self.LO_AMP < (2 ** 17 / self.CORDIC_GAIN), "LO_AMP saturate!"
        dds = DDS(amp=self.LO_AMP, num=self.num, den=self.den)
        self.rx = DSPCoreRX(num=self.num, den=self.den, dds=dds)
        self.tx = DSPCoreTX(num=self.num, den=self.den, dds=dds)
        self.submodules += self.rx.submodules
        self.submodules += self.tx.submodules
        # absolute max signal level
        self.max_adc_amp = (1 << 15) / np.abs(self.rx.gain) * 3.9

    def calc_open_loop_setp(self, amp_setpoint_adc, phs_setpoint_deg):
        """calculate open loop setpoint register values

        Args:
            amp_setpoint_adc (float): amplitude loop setpoint in ADC counts.
            phs_setpoint_deg (float): phase loop setpoint in degrees.

        Returns:
            amplitude and phase loop setpoint values in ADC counts
        """
        # scaling to compensate open loop setpoint (after PID)
        amp_setpoint = amp_setpoint_adc / np.abs(self.tx.gain)
        phs_setpoint = phs_setpoint_deg / 360 * (1 << 18)
        return int(amp_setpoint), int(phs_setpoint)

    def calc_close_loop_setp(self, amp_setpoint_adc, phs_setpoint_deg):
        """calculate close loop setpoint register values

        Args:
            amp_setpoint_adc (float): amplitude loop setpoint in ADC counts.
            phs_setpoint_deg (float): phase loop setpoint in degrees.
        Returns:
            amplitude and phase loop setpoint values in ADC counts
        """
        # signal gain for open loop setpoint (before PID)
        amp_setpoint = amp_setpoint_adc * np.abs(self.rx.gain)
        phs_setpoint = phs_setpoint_deg / 360 * (1 << 18)
        return int(amp_setpoint), int(phs_setpoint)
