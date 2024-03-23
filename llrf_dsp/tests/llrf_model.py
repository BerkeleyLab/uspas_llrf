import numpy as np
from llrf_dsp import LLRFModule, DDS, DSPCoreRX, DSPCoreTX


class LLRFModel(LLRFModule):
    LO_AMP = 74840  # must < (2^17 / CORDIC_GAIN)

    configs = {
        'ALSU': {
            'DSP_CLK_CYCLE':    8.7,  # ns
            'NUM_DDS':          4,
            'DEN_DDS':          11,
            'CIC_BASE_PERIOD':  22,
            'SHIFT_BASE':       7,
            'SHIFT_INLK':       12
        },
        'USPAS': {
            'DSP_CLK_CYCLE':    8.7,  # ns
            'NUM_DDS':          4,
            'DEN_DDS':          23,
            'CIC_BASE_PERIOD':  23,
            'SHIFT_BASE':       7,
            'SHIFT_INLK':       12
        },
        'LEMP': {
            'DSP_CLK_CYCLE':    8.4,  # ns
            'NUM_DDS':          3,
            'DEN_DDS':          14,
            'CIC_BASE_PERIOD':  28,
            'SHIFT_BASE':       7,
            'SHIFT_INLK':       13
        }
    }

    def __init__(self, conf='LEMP') -> None:
        """Math model that provides helper functions for simulation

        Args:
            conf (str): Application configuration name, in ['LEMP']
        """
        for k, v in self.configs[conf].items():
            setattr(self, k, v)
        super().__init__(self.NUM_DDS, self.DEN_DDS)
        dds = DDS(amp=self.LO_AMP, num=self.num, den=self.den)
        self.rx = DSPCoreRX(num=self.num, den=self.den, dds=dds)
        self.tx = DSPCoreTX(num=self.num, den=self.den, dds=dds)
        self.submodules += self.rx.submodules
        self.submodules += self.tx.submodules
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

    def gen_sinusoidal(self, amp=LO_AMP, ph_off=0, n_samples=256):
        """Generator of a sinusoidal wave of given parameters

        Args:
            amp (int, optional): amplitude. Defaults to LO_AMP (74840).
            ph_off (int, optional): phase offset in deg. Defaults to 0.
            n_samples (int, optional): number of samples for generator func.

        Returns:
            generator: yields from an array of complex values
        """
        t = np.arange(n_samples)
        samples = amp * np.exp(1j * (self.omega * t - np.deg2rad(ph_off)))
        yield from samples
