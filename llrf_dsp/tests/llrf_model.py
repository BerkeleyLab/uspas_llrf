import numpy as np


class MathModel:
    CORDIC_GAIN = 1.64676
    LO_AMP = 74840  # must < (2^17 / CORDIC_GAIN)
    n_samples = 256

    configs = {
        'LEMP': {
            'DSP_CLK_CYCLE':    8.4,
            'NUM_DDS':          3,
            'DEN_DDS':          14,
            'CIC_BASE_PERIOD':  28
        }
    }

    def __init__(self, conf='LEMP') -> None:
        """Math model that provides helper functions for simulation

        Args:
            conf (str): Applicaiton configration name, in ['LEMP']
        """
        for k, v in self.configs[conf].items():
            setattr(self, k, v)
        self.omega = np.pi * 2 * self.NUM_DDS / self.DEN_DDS  # non_iq angle

    def gen_signal(self, amp=LO_AMP, ph_off=0):
        """Generator of a sinusoidal wave of given parameters

        Args:
            amp (int, optional): amplitude. Defaults to LO_AMP (74840).
            ph_off (int, optional): phase offset in Radian. Defaults to 0.

        Returns:
            generator: yields from an array of complex values
        """
        t = np.arange(self.n_samples)
        samples = amp * np.exp(1j * (self.omega * t - ph_off))
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
        def calc_coeff_mat(n=0, omega=self.omega):
            return np.array([
                [np.sin(omega * (n + 1)), -np.sin(omega * n)],
                [-np.cos(omega * (n + 1)), np.cos(omega * n)]
            ])
        gain = 1 / np.sin(self.omega)
        s_pre = adc_data[0]
        for i, s in enumerate(adc_data[1:self.n_samples+1]):
            i, q = gain * calc_coeff_mat(i) @ np.array([s_pre, s])
            s_pre = s
            yield i + 1j*q
