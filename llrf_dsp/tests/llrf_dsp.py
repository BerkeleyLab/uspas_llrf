import numpy as np

CORDIC_GAIN = 1.646760258


class LLRFModule:
    def __init__(self, num: int = 4,  den: int = 11) -> None:
        """Base class for LLRF DSP module

        Args:
            num (int, optional): numerator of IF / Fs. Defaults to 4.
            den (int, optional): denominator of IF / Fs. Defaults to 11.
        """
        self.num, self.den = num, den
        self.omega = 2 * np.pi * self.num / self.den  # non_iq angle
        self._gain = 1

    @property
    def gain(self) -> np.complex128:
        return self._gain

    @gain.setter
    def gain(self, val) -> None:
        self._gain = val

    def __repr__(self):
        return (f"{self.__class__.__name__}:   "
                f"Amplitude gain={np.abs(self.gain):6.3f};   "
                f"Phase gain={np.angle(self.gain, deg=True):6.3f} deg")


class DDS(LLRFModule):
    def __init__(
            self, amp: int = 74840, width: int = 18,
            num: int = 4,  den: int = 11) -> None:
        """ Direct Digital Synthesizer using a phase accumulator and a CORDIC,
        which is in Polar -> Rect mode.
        Gateware: ph_acc.v and cordicg_b22.v.

        Args:
            amp (int): 18-bit integer of x_in port to CORDIC.
                Defaults to 74840, which is 94% full range.
            width (int): data width of CORDIC and the sinusoidal output ports.
            num (int): numerator of IF / Fs. Defaults to 4.
            den (int): denominator of IF / Fs. Defaults to 11.
        """
        super().__init__(num, den)
        self.width = width
        self.amp = amp

    @property
    def amp(self) -> int:
        return self._amp

    @amp.setter
    def amp(self, val: int) -> None:
        self._amp = val
        self.gain = CORDIC_GAIN * self._amp / (1 << self.width)
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
            Gateware: noniq_ddc.v and fiq_interp.v.

        Args:
            num (int): numerator of IF / Fs. Defaults to 4.
            den (int): denominator of IF / Fs. Defaults to 11.
        """
        super().__init__(num, den)
        self.gain = np.sin(self.omega) * 8


class WashoutFilter(LLRFModule):
    def __init__(self, num: int = 4, den: int = 11) -> None:
        """DC blocking 'washout` filter.
            Gateware: fwashout.v

        Args:
            num (int): numerator of IF / Fs. Defaults to 4.
            den (int): denominator of IF / Fs. Defaults to 11.
        """
        super().__init__(num, den)
        cut = 4
        N = 2**cut
        z = np.exp(1j * self.omega)
        self.gain = (z - 1) / (z * (z - (N - 1)/N))
