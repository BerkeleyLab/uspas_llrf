import numpy as np
from llrf_dsp import LLRFModule, DDS, DDC, WashoutFilter

CORDIC_GAIN = 1.646760258


class LLRFModel(LLRFModule):
    LO_AMP = 74840  # must < (2^17 / CORDIC_GAIN)

    configs = {
        'ALSU': {
            'DSP_CLK_CYCLE':    8.7,  # ns
            'NUM_DDS':          4,
            'DEN_DDS':          11,
            'CIC_BASE_PERIOD':  22,
            # 'DDC_AMP_GAIN':     2.8425,
            'DDC_PHS_GAIN':     0,
            # 'AMP_SETP_GAIN':    4.8312645,
            'SHIFT_BASE':       7,
            'SHIFT_INLK':       12
        },
        'USPAS': {
            'DSP_CLK_CYCLE':    8.7,  # ns
            'NUM_DDS':          4,
            'DEN_DDS':          23,
            'CIC_BASE_PERIOD':  23,
            # 'DDC_AMP_GAIN':     3.3396,
            'DDC_PHS_GAIN':     62.60869,  # 1 cycle
            # 'AMP_SETP_GAIN':    5.66806,
            'SHIFT_BASE':       7,
            'SHIFT_INLK':       12
        },
        'LEMP': {
            'DSP_CLK_CYCLE':    8.4,  # ns
            'NUM_DDS':          3,
            'DEN_DDS':          14,
            'CIC_BASE_PERIOD':  28,
            # 'DDC_AMP_GAIN':     3.66673,
            'DDC_PHS_GAIN':     102.85714,  # 6 cycles
            # 'AMP_SETP_GAIN':    6.22830,
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

        self.dds = DDS(amp=self.LO_AMP, num=self.NUM_DDS, den=self.DEN_DDS)
        self.ddc = DDC(num=self.NUM_DDS, den=self.DEN_DDS)
        self.fwashout = WashoutFilter(num=self.NUM_DDS, den=self.DEN_DDS)
        self.gain_rx = self.dds.gain * self.fwashout.gain * self.ddc.gain
        self.gain_tx = self.dds.gain * CORDIC_GAIN

    def calc_cic_gain(self, wave_sample_per=1):
        """calculate CIC filter gain in waveforms

        Args:
            wave_sample_per (int, optional): waveform sample period.
              Defaults to 1.

        Returns:
            shift (int): wave_shift register.
                Number of bits needs to be shifted to avoid saturation.
            mon_gain (float): total gain after CIC after shifting.
        """
        cic_R = wave_sample_per * self.CIC_BASE_PERIOD
        cic_bit_growth = 2 * np.log2(cic_R)
        cic_snr_bit_growth = np.log2(cic_R) / 2
        lo_dds_gain = self.LO_AMP * CORDIC_GAIN / (1 << 17)
        total_bit_growth = np.log2(lo_dds_gain) + cic_bit_growth
        full_shift = np.floor(total_bit_growth - cic_snr_bit_growth)
        wave_shift = max((full_shift - self.SHIFT_BASE), 0)
        mon_gain = 2**(
            total_bit_growth - self.SHIFT_BASE + 2 - 2 * self.wave_shift)
        return wave_shift, mon_gain

    def calc_open_loop_setpoint(self, amp_setpoint_adc, phs_setpoint_deg):
        """calculate open loop setpoint register values

        Args:
            amp_setpoint_adc (float): amplitude loop setpoint in ADC counts.
            phs_setpoint_deg (float): phase loop setpoint in degrees.

        Returns:
            amplitude and phase loop setpoint values in ADC counts
        """
        # scaling to compensate open loop setpoint (after PID)
        scale_open_loop_setp = 2 / self.gain_tx
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
        gain_close_loop = self.gain_rx * CORDIC_GAIN
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

    def gen_ddc_exp(self, adc_data):
        """Calculate expected I,Q values from 2 consecutive ADC samples using
            non-IQ down conversion:
        | I | = gain * | sin([n + 1] * omega) -sin(n * omega)| X |a_data[n]  |
        | Q |          |-cos([n + 1] * omega)  cos(n * omega)|   |a_data[n+1]|
        where gain is 1 / sin(omega).

        Args:
            adc_data (np.array): time series data samples for down conversion,
                the first (n_samples+1) elements are used.

        Returns:
            generator: yields complex value after down conversion.
        """
        def calc_coefficient_mat(n=0, omega=self.omega):
            return np.array([
                [np.sin(omega * (n + 1)), -np.sin(omega * n)],
                [-np.cos(omega * (n + 1)), np.cos(omega * n)]
            ])
        gain = 1 / np.sin(self.omega)
        s_pre = adc_data[0]
        for i, s in enumerate(adc_data[1:self.n_samples+1]):
            i, q = gain * calc_coefficient_mat(i) @ np.array([s_pre, s])
            s_pre = s
            yield i + 1j*q
