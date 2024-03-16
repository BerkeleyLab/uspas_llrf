import numpy as np
from scipy import signal


class LLRFModel:
    CORDIC_GAIN = 1.64676
    LO_AMP = 74840  # must < (2^17 / CORDIC_GAIN)
    n_samples = 256

    configs = {
        'ALSU': {
            'DSP_CLK_CYCLE':    8.7,  # ns
            'NUM_DDS':          4,
            'DEN_DDS':          11,
            'CIC_BASE_PERIOD':  22,
            'AMP_SETP_GAIN':    4.8312645,
            'SHIFT_BASE':       7,
            'SHIFT_INLK':       12
        },
        'USPAS': {
            'DSP_CLK_CYCLE':    8.7,  # ns
            'NUM_DDS':          4,
            'DEN_DDS':          23,
            'CIC_BASE_PERIOD':  23,
            'AMP_SETP_GAIN':    5.66806,
            'SHIFT_BASE':       7,
            'SHIFT_INLK':       12
        },
        'LEMP': {
            'DSP_CLK_CYCLE':    8.4,  # ns
            'NUM_DDS':          3,
            'DEN_DDS':          14,
            'CIC_BASE_PERIOD':  28,
            'AMP_SETP_GAIN':    6.22830,
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
        self.omega = 2 * np.pi * self.NUM_DDS / self.DEN_DDS  # non_iq angle

    def freqz_fwashout(self, cut=4):
        """calculate frequency response of fwashout.v:
            let N = 2^cut
            The filter has a z-plane zero at DC [1 + 0j]
            and 2 poles [0 + 0j], [(N-1)/N + 0j]
        Args:
            cut (int, optional): parameter of fwashout.v. Defaults to 4.

        Returns:
            frequency response at Fs = np.pi * 2 * NUM_DDS / DEN_DDS,
            as a complex number
        """
        N = 2**cut
        z, p, k = [1], [0, (N - 1) / N], 1
        w, h = signal.freqz_zpk(z, p, k, worN=[self.omega])
        return h[0]

    def freqz_noniq_ddc(self):
        """calculate non IQ down conversion (noniq_ddc.v) frequency response

        Returns:
            frequency response at Fs = np.pi * 2 * NUM_DDS / DEN_DDS,
            as a complex number
        """
        return 1 / np.sin(self.omega)

    def calc_dds_config(self):
        """calculate DDS registers based on NUM_DDS / DEN_DDS.

        Returns:
            phase_step_h, phase_step_l, modulo registers.
        """
        m = 4096 / self.DEN_DDS
        modulo = 4096 - m * self.DEN_DDS
        r = (1 << 20) * self.NUM_DDS
        phase_step_h = int(r / self.DEN_DDS)
        phase_step_l = int(r / self.DEN_DDS)
        return phase_step_h, phase_step_l, modulo

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
        lo_dds_gain = self.LO_AMP * self.CORDIC_GAIN / (1 << 17)
        total_bit_growth = np.log2(lo_dds_gain) + cic_bit_growth
        full_shift = np.floor(total_bit_growth - cic_snr_bit_growth)
        self.wave_shift = max((full_shift - self.SHIFT_BASE), 0)
        self.mon_gain = 2**(
            total_bit_growth - self.SHIFT_BASE + 2 - 2 * self.wave_shift)
        return self.wave_shift, self.mon_gain

    def calc_loop_gain(self, amp_setpoint_adc, phs_setpoint_deg):
        """calculate open / close loop setpoint register values

        Args:
            amp_setpoint_adc (float): amplitude loop setpoint in ADC counts.
            phs_setpoint_deg (float): phase loop setpoint in degrees.
        """
        open_loop_gain = (1 << 19) / (self.CORDIC_GAIN**2 * self.LO_AMP)
        self.amp_setpoint_open = amp_setpoint_adc * open_loop_gain
        self.phs_setpoint_open = phs_setpoint_deg / 360 * (1 << 18)
        self.amp_setpoint_close = amp_setpoint_adc * self.AMP_SETP_GAIN
        self.phs_setpoint_close = self.phs_setpoint_open

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
