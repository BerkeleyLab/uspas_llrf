import numpy as np
from matplotlib import pyplot as plt
from scipy.optimize import curve_fit


'''
Total RX gain:
    washout filter gain *
    ddc gain (including interpolation) *
    DDS gain *
    CIC buffer gain (runtime configurable depending on decimation)

Calibration:
    Feed a close to full scale signal to the ADCs at a known power
    Read the fraction of FS from the cic buffer using the scale factor
    Calculate what power would be FS of the ADC
'''


class rx_theory_gain():
    def __init__(self, cut, num, den, wave_samp_per,
                 cic_base_period, shift_base, amp,
                 verbose=False):
        self.cut = cut
        self.num = num
        self.den = den
        self.wave_samp_per = wave_samp_per
        self.cic_base_period = cic_base_period
        self.shift_base = shift_base
        self.CORDIC_GAIN = 1.646760258
        self.amp = amp
        self.verbose = verbose

    def washout_gain(self):
        N = 2**self.cut
        p = (N - 1) / N
        z = np.exp(2j * np.pi * self.num / self.den)
        gain = (z - 1) / z / (z - p)
        print("Washout filter gain:\t%.8f" % abs(gain))
        self.w_g = abs(gain)

    def ddc_gain(self):
        # Factor of 2 is the interpolate gain
        gain = np.sin(2 * np.pi * self.num / self.den) * 2
        print("DDC gain:\t\t%.8f" % abs(gain))
        self.ddc_g = abs(gain)

    def dds_gain(self):
        width = 17  # TODO: why?
        self.dds_g = self.CORDIC_GAIN * self.amp / (1 << width)
        print("DDS gain:\t\t%.8f" % self.dds_g)

    def ddc_dds_gain(self):
        self.ddc_dds_g = self.ddc_g * self.dds_g
        print("DDC * DDS gain:\t\t%.8f" % self.ddc_dds_g)

    def cic_gain(self):
        cic_R = self.wave_samp_per * self.cic_base_period
        cic_bit_growth = 2 * np.log2(cic_R)
        cic_snr_bit_growth = np.log2(cic_R / 2) / 2
        full_shift = np.floor(cic_bit_growth - cic_snr_bit_growth)
        wave_shift = np.ceil(max((full_shift - self.shift_base) / 2, 0))
        self.cic_g = 2**(cic_bit_growth - self.shift_base + 2 - 2 * wave_shift)
        if self.verbose:
            log_banner("CIC gain calculation")
            print("shift_base:\t\t%.2f" % self.shift_base)
            print("wave_samp_per:\t\t%.2f" % self.wave_samp_per)
            print("cic_base_period:\t%.2f" % self.cic_base_period)
            print("R:\t\t\t%.2f" % cic_R)
            print("bit growth:\t\t%.8f" % cic_bit_growth)
            print("SNR bit growth:\t\t%.8f" % cic_snr_bit_growth)
            print("full shift:\t\t%.2f" % full_shift)
            print("wave shift:\t\t%.2f" % wave_shift)
            print("exp:\t\t\t%.8f" % (cic_bit_growth - self.shift_base + 2
                                      - 2 * wave_shift))

        print("CIC gain:\t\t%.8f" % self.cic_g)


class rx_sim_gain():
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
        if (cic_gain_i - cic_gain_q) / cic_gain_i < 0.01:
            self.cic_g = cic_gain_i
            print("CIC gain:\t\t%.8f" % self.cic_g)
        else:
            print("CIC gain error")
            exit()

    def total_gain(self):
        self.cic_amp = np.sqrt(self.cic_i**2 + self.cic_q**2)
        self.total_g = self.cic_amp / self.raw_amp_fit
        print("Total gain:\t\t%.8f" % self.total_g)

    def fit_data(self, y_data, verbose=False):
        x_data = np.arange(0, len(y_data))
        # Initial guesses for A, f, phi, C
        initial_guess = [30000, 3 / 14, 0, 0]
        params, covariance = curve_fit(sine_wave, x_data, y_data,
                                       p0=initial_guess)
        A_fit, f_fit, phi_fit, C_fit = params

        # Generate fitted curve
        x_fit = np.linspace(0, len(x_data), 500)
        y_fit = sine_wave(x_fit, A_fit, f_fit, phi_fit, C_fit)

        if verbose:
            plt.plot(x_fit, y_fit, lw=3)
            plt.plot(x_data, y_data, '--o', lw=2)
            plt.show()

        return A_fit


def log_banner(my_str):
    print('*' * 10 + f"{my_str:^20s}" + '*' * 10)


# Define sine function to fit
def sine_wave(x, A, f, phi, C):
    return A * np.sin(2 * np.pi * f * x + phi) + C


if __name__ == "__main__":
    verbose = True

    log_banner("LEMP")
    log_banner("Theory gains:")
    cut = 4
    num = 3
    den = 14
    wave_samp_per = 2
    cic_base_period = 28
    shift_base = 7
    amp = 74840
    rx = rx_theory_gain(cut, num, den, wave_samp_per,
                        cic_base_period, shift_base, amp,
                        verbose)
    rx.washout_gain()
    rx.ddc_gain()
    rx.dds_gain()
    rx.ddc_dds_gain()
    total_rx_g = rx.w_g * rx.ddc_g * rx.dds_g
    print("Total RX gain:\t\t%.4f" % total_rx_g)
    rx.cic_gain()
    total_g = total_rx_g * rx.cic_g
    print("Total gain:\t\t%.4f" % total_g)

    print("\n")
    log_banner("Simulation gains:")
    raw_data = np.loadtxt("sim_adc_raw.txt")
    fw_data = np.loadtxt("fwashout_output.txt")
    ddc_i = 56860
    ddc_q = 15235
    cic_i = 348265
    cic_q = 93310
    rx_sim = rx_sim_gain(num, den, raw_data, fw_data, ddc_i, ddc_q,
                         cic_i, cic_q, verbose)
    rx_sim.washout_gain()
    rx_sim.ddc_dds_gain()
    total_rx_sim_g = rx_sim.w_g * rx_sim.ddc_dds_g
    print("Total RX gain:\t\t%.4f" % total_rx_sim_g)
    rx_sim.cic_gain()
    rx_sim.total_gain()
