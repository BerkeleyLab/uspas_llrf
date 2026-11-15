"""RX gain chain: theory from the LLRFShell model, measured from waveforms.

Total RX gain to the CIC waveform buffer:
    washout filter gain *
    DDC gain (including interpolation) *
    DDS gain *
    CIC waveform recorder gain (depends on wave_samp_per)

Calibration:
    Feed a close to full scale signal to the ADCs at a known power
    Read the fraction of FS from the cic buffer using the scale factor
    Calculate what power would be FS of the ADC
"""
import numpy as np
from matplotlib import pyplot as plt
from uspas_llrf.model.dsp import WashoutFilter, DDS, DDC
from uspas_llrf.utils import fit_sine


def rx_theory_gains(model, verbose=True):
    """Theoretical RX gains of an LLRFShell model (e.g. LLRFApp.model), for
    its design and wave_samp_per. Returns a dict of magnitudes: washout,
    dds, ddc, cic (the CIC waveform recorder, with the wave_shift the model
    writes) and total, which is abs(model.cic_wfm_gain).
    """
    stages = {type(m): abs(m.gain) for m in model.rx.submodules}
    gains = {
        'washout': stages[WashoutFilter],
        'dds': stages[DDS],
        'ddc': stages[DDC],
        'cic': abs(model.cic_mon.gain),
        'total': abs(model.cic_wfm_gain),
    }
    if verbose:
        cic = model.cic_mon
        log_banner('RX theory gains')
        print(f"wave_samp_per:\t\t{cic.wave_samp_per}")
        print(f"CIC R:\t\t\t{cic.wave_samp_per * cic.cic_base_period}")
        print(f"cic_wave_shift:\t\t{cic.wave_shift}")
        for k, v in gains.items():
            print(f"{k + ' gain:':24s}{v:.8f}")
    return gains


class rx_sim_gain():
    """RX gains measured from waveforms: raw ADC, washout filter output,
    DDC and CIC I/Q values."""
    def __init__(self, num, den, raw_data,
                 fw_data, ddc_i, ddc_q,
                 cic_i, cic_q, verbose=False):
        self.num = num
        self.den = den
        self.raw_data = raw_data
        self.fw_data = fw_data
        self.ddc_i = ddc_i
        self.ddc_q = ddc_q
        self.cic_i = cic_i
        self.cic_q = cic_q
        self.verbose = verbose

    def washout_gain(self):
        self.raw_amp_fit = self.fit_data(self.raw_data, self.verbose)
        self.fwa_amp_fit = self.fit_data(self.fw_data, self.verbose)
        self.w_g = self.fwa_amp_fit / self.raw_amp_fit
        print("Washout filter gain:\t%.8f" % self.w_g)

    def ddc_dds_gain(self):
        self.ddc_amp = np.sqrt(self.ddc_i**2 + self.ddc_q**2)
        # Factor of 2 is the interpolate gain
        self.ddc_dds_g = abs(self.ddc_amp / self.fwa_amp_fit) * 2
        print("DDC * DDS gain:\t\t%.8f" % self.ddc_dds_g)

    def cic_gain(self):
        cic_gain_i = self.cic_i / self.ddc_i
        cic_gain_q = self.cic_q / self.ddc_q
        if abs(cic_gain_i - cic_gain_q) / abs(cic_gain_i) >= 0.01:
            raise ValueError(f"CIC gain I {cic_gain_i:.6f} and Q {cic_gain_q:.6f} differ by more than 1%")
        self.cic_g = cic_gain_i
        print("CIC gain:\t\t%.8f" % self.cic_g)

    def total_gain(self):
        self.cic_amp = np.sqrt(self.cic_i**2 + self.cic_q**2)
        self.total_g = self.cic_amp / self.raw_amp_fit
        print("Total gain:\t\t%.8f" % self.total_g)

    def fit_data(self, y_data, verbose=False):
        # Initial guesses for A, f, phi, C: the IF at num/den of the sample rate
        x_fit, y_fit, A_fit = fit_sine(y_data, [30000, self.num / self.den, 0, 0])
        if verbose:
            plt.plot(x_fit, y_fit, lw=3)
            plt.plot(np.arange(len(y_data)), y_data, '--o', lw=2)
            plt.show()
        return A_fit


def log_banner(my_str):
    print('*' * 10 + f"{my_str:^20s}" + '*' * 10)
