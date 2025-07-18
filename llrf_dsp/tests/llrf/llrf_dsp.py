import numpy as np


class LLRFModule:
    CORDIC_GAIN = 1.646760258

    def __init__(self, num: int = 4,  den: int = 11) -> None:
        """Base class for LLRF DSP module

        Args:
            num (int, optional): numerator of IF / Fs. Defaults to 4.
            den (int, optional): denominator of IF / Fs. Defaults to 11.
        """
        self.num, self.den = num, den
        self.omega = 2 * np.pi * self.num / self.den  # non_iq angle
        self.z = np.exp(1j * self.omega)
        self._gain = 1
        self._submodules = []

    @property
    def gain(self) -> np.complex128:
        return self._gain

    @gain.setter
    def gain(self, val) -> None:
        self._gain = val

    @property
    def submodules(self) -> list:
        return self._submodules

    @submodules.setter
    def submodules(self, val) -> None:
        self._submodules = val
        self._gain = 1
        for m in val:
            self._gain *= m.gain

    def __repr__(self):
        str = (f"< {self.__class__.__name__:12s}:   "
               f"Amp gain={np.abs(self.gain):6.3f},   "
               f"Phs gain={np.angle(self.gain, deg=True):8.2f} deg >\n")
        for m in self.submodules:
            str += (f"{m.__class__.__name__:14s}:   "
                    f"Amp gain={np.abs(m.gain):6.3f},   "
                    f"Phs gain={np.angle(m.gain, deg=True):8.2f} deg;\n")
        return str


class DDS(LLRFModule):
    def __init__(
            self, amp: int = 74840, width: int = 18,
            num: int = 4,  den: int = 11) -> None:
        """ Direct Digital Synthesizer using a phase accumulator and a CORDIC,
        which is in Polar -> Rect mode.
        Gateware: ph_acc.v and cordicg_b22.v.

        Args:
            amp (int): 18-bit integer of x_in port to CORDIC.
                Defaults to 74840, which is 94% full range of 17-bit value.
            width (int): data width of CORDIC and the sinusoidal output ports.
            num (int): numerator of IF / Fs. Defaults to 4.
            den (int): denominator of IF / Fs. Defaults to 11.
        """
        super().__init__(num, den)
        self.width = width - 1
        self.amp = amp

    @property
    def amp(self) -> int:
        return self._amp

    @amp.setter
    def amp(self, val: int) -> None:
        self._amp = val
        self.gain = self.CORDIC_GAIN * self._amp / (1 << self.width)
        assert self.gain < 1.0, f"NCO saturates: gain={self.gain}."

    def calc_dds_config(self):
        """calculate phase accumulator register values.
        """
        m = 4096 / self.den
        modulo = 4096 - m * self.den
        r = (1 << 20) * self.num
        phase_step_h = int(r / self.den)
        phase_step_l = int(r / self.den)
        return phase_step_h, phase_step_l, modulo


class DDC(LLRFModule):
    def __init__(self, num: int = 4,  den: int = 11) -> None:
        """Non-IQ Digital Down-Conversion.
            Gateware: noniq_ddc.v: gain=sin(2 * pi * theta),
                     fiq_interp.v: gain=2.

        Args:
            num (int): numerator of IF / Fs. Defaults to 4.
            den (int): denominator of IF / Fs. Defaults to 11.
        """
        super().__init__(num, den)
        self.gain = np.sin(self.omega) * 2 * self.z**(-self.den+2)

    def gen_ddc_data(self, adc_data):
        """Calculate I,Q values from 2 consecutive ADC samples using
            non-IQ down conversion:
        | I | = gain * | sin([n + 1] * omega) -sin(n * omega)| X |a_data[n]  |
        | Q |          | cos([n + 1] * omega) -cos(n * omega)|   |a_data[n+1]|
        where gain is 1 / sin(omega).

        Args:
            adc_data (np.array): time series data samples for down conversion

        Returns:
            generator: yields complex value after down conversion.
        """
        def calc_coefficient_mat(n=0, omega=self.omega):
            return np.array([
                [np.sin(omega * (n + 1)), -np.sin(omega * n)],
                [np.cos(omega * (n + 1)), -np.cos(omega * n)]
            ])
        gain = 1 / np.sin(self.omega)
        s_pre = adc_data[0]
        for n, s in enumerate(adc_data[1:]):
            i, q = gain * calc_coefficient_mat(n) @ np.array([s_pre, s])
            s_pre = s
            yield i + 1j * q

    def calc_ddc_raw(self, adc_data):
        """
        Digital Down Conversion from raw ADC data, using non-IQ matrix over
        adjacent samples. This will result in one less sample. Pad the result
        with trailing element to match input data shape.

        Args:
            adc_data (np.array): time series data samples for down conversion

        Returns:
            ddc_data (np.array): complex array after down conversion.
        """
        return np.pad(list(self.gen_ddc_data(adc_data)), (0, 1), 'edge')


class WashoutFilter(LLRFModule):
    def __init__(self, num: int = 4, den: int = 11) -> None:
        """DC blocking 'washout` filter.
            Gateware: fwashout.v

        Args:
            num (int): numerator of IF / Fs. Defaults to 4.
            den (int): denominator of IF / Fs. Defaults to 11.
        """
        super().__init__(num, den)
        self.gain = (self.z - 1) / (self.z * (self.z - 15/16))


class CORDIC(LLRFModule):
    def __init__(self, num: int = 4, den: int = 11,
                 phase_off_deg: float = 0) -> None:
        """Receiver or Transceiver CORDIC.
            Gateware: cordicg_b22.v (rx_cordic or tx_cordic).

        Args:
            num (int): numerator of IF / Fs. Defaults to 4.
            den (int): denominator of IF / Fs. Defaults to 11.
            phase_off_deg (float): Phase offset in degrees.
        """
        super().__init__(num, den)
        self.gain = self.CORDIC_GAIN * np.exp(1j * np.deg2rad(phase_off_deg))


class CICWaveRecorder(LLRFModule):
    def __init__(self, num: int = 4, den: int = 11,
                 cic_base_period: int = 22,
                 shift_base: int = 7,
                 wave_samp_per: int = 1) -> None:
        """Waveform recorder with Cascaded Integrator-Comb Filter.
            Decimation factor = cic_period * wave_samp_per.
            Contains separate DDS LO for waveform down conversion.
            Gateware: cic_wave_recorder.v, cic_timing.v, etc.

        Args:
            num (int): numerator of IF / Fs. Defaults to 4.
            den (int): denominator of IF / Fs. Defaults to 11.
            lo_amp (int): amp parameter of LO DDS.
                Defaults to 74840, which is 94% full range.
            cic_base_period (int): base period for cic_timing.
              Must be multiple of den. Defaults to 22.
            shift_base (int): scaling factor as cc_shift_base parameter.
                number of bits to discard to avoid saturation.
            wave_samp_per (int): wave sample period.
        """
        super().__init__(num, den)
        self.shift_base = shift_base
        self.cic_base_period = cic_base_period
        assert self.cic_base_period % self.den == 0, \
            "CIC base period must be multiple of DEN."
        self.gain = self.calc_cic_gain(wave_samp_per)

    def calc_cic_gain(self, wave_samp_per):
        """calculate CIC filter gain in waveforms
            wave_shift register is calculated based on wave_sample_per.
            It is the number of bits needs to be shifted to avoid saturation.

        Returns:
            mon_gain (float): total gain after CIC after shifting.
        """
        cic_R = wave_samp_per * self.cic_base_period
        cic_bit_growth = 2 * np.log2(cic_R)
        cic_snr_bit_growth = np.log2(cic_R) / 2
        full_shift = np.floor(cic_bit_growth - cic_snr_bit_growth)
        self.wave_shift = max((full_shift - self.shift_base)/2, 0)
        mon_gain = 2**(
            cic_bit_growth - self.shift_base + 2 - 2 * self.wave_shift)
        return mon_gain


class DSPCoreRX(LLRFModule):
    def __init__(self, num: int = 4, den: int = 11,
                 dds: DDS = None) -> None:
        """Receiver DSP chain in dsp_core.v.
            Gateware: fwashout.v, noniq_ddc.v, fiq_interp.v, rx_cordic

        Args:
            num (int): numerator of IF / Fs. Defaults to 4.
            den (int): denominator of IF / Fs. Defaults to 11.
            dds (DDS): external dds shared with tx.
        """
        super().__init__(num, den)
        if dds is None:
            dds = DDS(amp=74840, num=num, den=den)

        self.submodules += [
            WashoutFilter(num=num, den=den),
            dds,
            DDC(num=num, den=den)]
        self.phase_off_deg = np.angle(self.gain, deg=True)
        # compensate phase gain of upstream modules
        self.rx_cordic = CORDIC(
            num=num, den=den, phase_off_deg=-self.phase_off_deg)
        self.submodules += [self.rx_cordic]


class DUC(LLRFModule):
    def __init__(self, num: int = 4,  den: int = 11) -> None:
        """Non-IQ Digital Up-Conversion.
            Gateware: flevel_set.v.

        Args:
            num (int): numerator of IF / Fs. Defaults to 4.
            den (int): denominator of IF / Fs. Defaults to 11.
        """
        super().__init__(num, den)
        self.gain = 1/4 * self.z**(-3)


class DSPCoreTX(LLRFModule):
    def __init__(self, num: int = 4, den: int = 11,
                 dds: DDS = None) -> None:
        """Transmitter DSP chain in dsp_core.v.
            Gateware: tx_cordic, flevel_set.v

        Args:
            num (int): numerator of IF / Fs. Defaults to 4.
            den (int): denominator of IF / Fs. Defaults to 11.
            dds (DDS): external dds shared with rx.
        """
        super().__init__(num, den)
        if dds is None:
            dds = DDS(amp=74840, num=num, den=den)

        self.submodules += [
            dds,
            DUC(num=num, den=den)]
        self.phase_off_deg = np.angle(self.gain, deg=True)
        self.tx_cordic = CORDIC(
            num=num, den=den, phase_off_deg=-self.phase_off_deg)
        self.submodules += [self.tx_cordic]
