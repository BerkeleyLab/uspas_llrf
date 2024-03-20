import numpy as np
from llrf_dsp import LLRFModule, DSPCoreRX, DSPCoreTX


class LLRFModel(LLRFModule):
    LO_AMP = 74840  # must < (2^17 / CORDIC_GAIN)

    configs = {
        'ALSU': {
            'DSP_CLK_CYCLE':    8.7,  # ns
            'NUM_DDS':          4,
            'DEN_DDS':          11,
            'CIC_BASE_PERIOD':  22,
            'DDC_PHS_GAIN':     0,
            'RX_LO_PHS_DEG':    -130.065,
            'TX_LO_PHS_DEG':    -130.909,
            'SHIFT_BASE':       7,
            'SHIFT_INLK':       12
        },
        'USPAS': {
            'DSP_CLK_CYCLE':    8.7,  # ns
            'NUM_DDS':          4,
            'DEN_DDS':          23,
            'CIC_BASE_PERIOD':  23,
            'DDC_PHS_GAIN':     62.60869,  # 1 cycle
            'RX_LO_PHS_DEG':    -59.57,
            'TX_LO_PHS_DEG':    0,
            'SHIFT_BASE':       7,
            'SHIFT_INLK':       12
        },
        'LEMP': {
            'DSP_CLK_CYCLE':    8.4,  # ns
            'NUM_DDS':          3,
            'DEN_DDS':          14,
            'CIC_BASE_PERIOD':  28,
            'DDC_PHS_GAIN':     102.85714,  # 6 cycles
            'RX_LO_PHS_DEG':    182.32,
            'TX_LO_PHS_DEG':    25.71,
            'SHIFT_BASE':       7,
            'SHIFT_INLK':       13
        }
    }

    def __init__(self, conf='LEMP', n_samples=256) -> None:
        """Math model that provides helper functions for simulation

        Args:
            conf (str): Application configuration name, in ['LEMP']
            n_samples (int, optional): number of samples for generator func.
        """
        for k, v in self.configs[conf].items():
            setattr(self, k, v)
        super().__init__(self.NUM_DDS, self.DEN_DDS)
        self.n_samples = n_samples

        self.rx = DSPCoreRX(
            lo_amp=self.LO_AMP, num=self.num, den=self.den,
            phase_off_deg=self.RX_LO_PHS_DEG)
        self.tx = DSPCoreTX(
            lo_amp=self.LO_AMP, num=self.num, den=self.den,
            phase_off_deg=self.TX_LO_PHS_DEG)

    def calc_open_loop_setpoint(self, amp_setpoint_adc, phs_setpoint_deg):
        """calculate open loop setpoint register values

        Args:
            amp_setpoint_adc (float): amplitude loop setpoint in ADC counts.
            phs_setpoint_deg (float): phase loop setpoint in degrees.

        Returns:
            amplitude and phase loop setpoint values in ADC counts
        """
        # scaling to compensate open loop setpoint (after PID)
        scale_open_loop_setp = 2 / self.tx.gain
        amp_setpoint = amp_setpoint_adc * scale_open_loop_setp
        phs_setpoint = phs_setpoint_deg / 360 * (1 << 18)
        return amp_setpoint, phs_setpoint

    def calc_close_loop_setpoint(self, amp_setpoint_adc, phs_setpoint_deg):
        """calculate close loop setpoint register values

        Args:
            amp_setpoint_adc (float): amplitude loop setpoint in ADC counts.
            phs_setpoint_deg (float): phase loop setpoint in degrees.
        Returns:
            amplitude and phase loop setpoint values in ADC counts
        """
        # signal gain for open loop setpoint (before PID)
        gain_close_loop = self.rx.gain
        amp_setpoint = amp_setpoint_adc * gain_close_loop
        phs_setpoint = phs_setpoint_deg / 360 * (1 << 18)
        return amp_setpoint, phs_setpoint

    def gen_sinusoidal(self, amp=LO_AMP, ph_off=0):
        """Generator of a sinusoidal wave of given parameters

        Args:
            amp (int, optional): amplitude. Defaults to LO_AMP (74840).
            ph_off (int, optional): phase offset in deg. Defaults to 0.

        Returns:
            generator: yields from an array of complex values
        """
        t = np.arange(self.n_samples)
        samples = amp * np.exp(1j * (self.omega * t - np.deg2rad(ph_off)))
        yield from samples
