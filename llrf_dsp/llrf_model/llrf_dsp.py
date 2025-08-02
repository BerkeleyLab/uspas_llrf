import numpy as np
import json
from dataclasses import dataclass, field
import argparse
import pprint


def wrap_phase(phs: float, deg=True):
    """Wrap phase value to be within [-180, 180] or [-pi, pi].
    """
    scale = 180 if deg else np.pi
    return (phs + scale) % (2 * scale) - scale


def clamp(value, min_value, max_value):
    return max(min_value, min(value, max_value))


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
        self.phase_step_h, self.phase_step_l, self.modulo = \
            self.calc_dds_config()
        self.dwh = 20  # high part of phase step
        self.dwl = 32 - self.dwh  # low part of phase step
        self.phase_step = (self.phase_step_h << self.dwl) | self.phase_step_l

    @property
    def amp(self) -> int:
        return self._amp

    @amp.setter
    def amp(self, val: int) -> None:
        self._amp = val
        self.gain = self.CORDIC_GAIN * self._amp / (1 << self.width)
        assert self.gain < 1.0, f"NCO saturates: gain={self.gain}."

    def calc_dds_config(self, dwh: int = 20, dwl: int = 12) -> tuple:
        """calculate phase accumulator register values.
        """
        m = int((1 << dwl) / self.den)
        modulo = (1 << dwl) % self.den
        r = (1 << dwh) * self.num
        phase_step_h = int(r / self.den) & (2**dwh - 1)
        phase_step_l = int((r % self.den) * m) & (2**dwl - 1)
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
        self.wave_samp_per = wave_samp_per

    def calc_cic_gain(self, wave_samp_per):
        """calculate CIC filter gain in waveforms
            wave_shift register is calculated based on wave_sample_per.
            It is the number of bits needs to be shifted to avoid saturation.

        Returns:
            gain (float): total gain after CIC after shifting.
        """
        cic_R = wave_samp_per * self.cic_base_period
        cic_bit_growth = 2 * np.log2(cic_R)
        cic_snr_bit_growth = np.log2(cic_R / 2) / 2
        full_shift = np.floor(cic_bit_growth - cic_snr_bit_growth)
        self._wave_shift = int(max((full_shift - self.shift_base) / 2, 0))
        self._gain = 2**(cic_bit_growth - self.shift_base + 2
                         - 2 * self._wave_shift)

    @property
    def gain(self):
        return self._gain

    @property
    def wave_shift(self):
        return self._wave_shift

    @property
    def wave_samp_per(self):
        return self._wave_samp_per

    @wave_samp_per.setter
    def wave_samp_per(self, val):
        self._wave_samp_per = val
        self.calc_cic_gain(val)


class DSPCoreRX(LLRFModule):
    def __init__(self, num: int = 4, den: int = 11,
                 has_cordic: bool = True,
                 dds: DDS = None) -> None:
        """Receiver DSP chain in dsp_core.v.
            Gateware: ddc.v, rx_cordic.v

        Args:
            num (int): numerator of IF / Fs. Defaults to 4.
            den (int): denominator of IF / Fs. Defaults to 11.
            dds (DDS): external dds.
        """
        super().__init__(num, den)
        if dds is None:
            dds = DDS(amp=74840, num=num, den=den)
        self.dds = dds
        self.submodules += [
            WashoutFilter(num=num, den=den),
            dds,
            DDC(num=num, den=den)]
        if has_cordic:  # in dsp_core.v
            self.phase_off_deg = np.angle(self.gain, deg=True)
            # compensate phase gain of upstream modules
            self.rx_cordic = CORDIC(
                num=num, den=den, phase_off_deg=-self.phase_off_deg)
            self.submodules += [self.rx_cordic]


class DUC(LLRFModule):
    def __init__(self, num: int = 4,  den: int = 11, pipeline: int = 3):
        """Non-IQ Digital Up-Conversion.
            Gateware: cpxmul_fullspeed.v.

        Args:
            num (int): numerator of IF / Fs. Defaults to 4.
            den (int): denominator of IF / Fs. Defaults to 11.
        """
        super().__init__(num, den)
        self.gain = self.z**(-pipeline)


class DSPCoreTX(LLRFModule):
    def __init__(self, num: int = 4, den: int = 11,
                 has_cordic: bool = True,
                 duc_pipeline: int = 3,
                 dds: DDS = None) -> None:
        """Transmitter DSP chain.
            Gateware: tx_cordic.v, cpxmul_fullspeed.v

        Args:
            num (int): numerator of IF / Fs. Defaults to 4.
            den (int): denominator of IF / Fs. Defaults to 11.
            dds (DDS): external DDS.
        """
        super().__init__(num, den)
        if dds is None:
            dds = DDS(amp=74840, num=num, den=den)
        self.dds = dds

        self.submodules += [
            dds,
            DUC(num=num, den=den, pipeline=duc_pipeline)]
        self.duc_pipeline = duc_pipeline
        self.phase_off_deg = np.angle(self.gain, deg=True)
        if has_cordic:  # in dsp_core.v
            self.tx_cordic = CORDIC(
                num=num, den=den, phase_off_deg=-self.phase_off_deg)
            self.submodules += [self.tx_cordic]


@dataclass
class LLRFInitRegisters:
    """Initial register configuration for LLRF DSP module."""
    dds_phase_step: int = 0
    dds_phase_shift: int = 0
    dds_modulo: int = 0
    wave_samp_per: int = 1
    wave_shift: int = 0
    chan_keep: int = 0
    amp_setpoint: int = 0
    phs_setpoint: int = 0
    amp_loop_enable: bool = False
    phs_loop_enable: bool = False
    amp_loop_reset: bool = False
    phs_loop_reset: bool = False
    dsp_reset: bool = False
    Kp_amp: int = 0
    Ki_amp: int = 0
    Kp_phs: int = 0
    Ki_phs: int = 0
    pulse_mode: bool = False
    pulse_high_len: int = 10
    dac_permit: bool = False
    slow_snap_sel: bool = True

    def __setattr__(self, name, value):
        """Enforce data type casting, e.g. int"""
        annotations = getattr(self, '__annotations__', {})
        if name in annotations:
            expected_type = annotations[name]
            if not isinstance(value, expected_type):
                value = expected_type(value)
        super().__setattr__(name, value)


@dataclass
class LLRFCalibrationConfig:
    """Calibration configuration for LLRF DSP module."""
    rx_gain: float = 1.0  # ratio from ADC to controller
    tx_gain: float = 1.0  # ratio from controller to DAC
    rx_phase_off_deg: float = 0.0
    tx_phase_off_deg: float = 0.0
    mon_gain: float = 1.0
    inlk_gain: float = 1.0
    max_adc_input: float = (1 << 15) * 0.95  # absolute max input signal level
    max_dac_output: float = (1 << 15) * 0.95  # absolute max DAC output level
    max_amp_setpoint: float = field(init=False)  # max amplitude setpoint
    open_loop_gain: float = field(init=False)

    def __post_init__(self):
        """Post-initialization to calculate dependent fields."""
        self.max_amp_setpoint = self.max_dac_output / self.tx_gain
        self.open_loop_gain = self.tx_gain


class LLRFModel(LLRFModule):
    def __init__(self, conf='LEMP', settings_fname='settings.json',
                 wave_samp_per=1):
        """Math model that provides helper functions for simulation

        Args:
            conf (str): Application configuration key (aka FSET),
              in ['LEMP', 'ALSU', 'USPAS', 'AWA']
            settings_fname (str): configuration json file path
        """
        with open(settings_fname) as f:
            configs = json.load(f)
        for k, v in configs[conf].items():
            setattr(self, k, v)
        super().__init__(self.NUM_DDS, self.DEN_DDS)
        assert self.LO_AMP < (2 ** 17 / self.CORDIC_GAIN), "LO_AMP saturate!"
        self.wave_samp_per = wave_samp_per
        self.dds = dds = DDS(amp=self.LO_AMP, num=self.num, den=self.den)
        self.rx = DSPCoreRX(num=self.num, den=self.den, dds=dds)
        self.tx = DSPCoreTX(num=self.num, den=self.den, dds=dds)
        self.cic_inlk = CICWaveRecorder(
            num=self.num, den=self.den,
            cic_base_period=self.CIC_BASE_PERIOD, shift_base=self.SHIFT_INLK)
        self.cic_mon = CICWaveRecorder(
            num=self.num, den=self.den,
            cic_base_period=self.CIC_BASE_PERIOD,
            shift_base=self.SHIFT_BASE, wave_samp_per=self.wave_samp_per)
        self.submodules += self.rx.submodules
        self.submodules += self.tx.submodules

        print('xxx', self.cic_mon.wave_shift)
        # initialization parameters for simulation and SoC integration
        self.init_config = LLRFInitRegisters(
            dds_phase_step=self.dds.phase_step,
            dds_modulo=self.dds.modulo,
            wave_samp_per=self.wave_samp_per,
            wave_shift=self.cic_mon.wave_shift,
            chan_keep=0b11,
            Kp_amp=20, Ki_amp=50, Kp_phs=50, Ki_phs=200
        )

        self.cal_config = LLRFCalibrationConfig(
            rx_gain=np.abs(self.rx.gain),
            tx_gain=np.abs(self.tx.gain),
            rx_phase_off_deg=self.rx.phase_off_deg,
            tx_phase_off_deg=self.tx.phase_off_deg,
            mon_gain=self.mon_gain,
            inlk_gain=self.inlk_gain,
        )

    @property
    def mon_gain(self):
        """ CIC waveform recorder gain """
        return self.cic_mon.gain * np.abs(self.rx.gain) / self.CORDIC_GAIN / 4

    @property
    def inlk_gain(self):
        """ Interlock IQ stream gain """
        return self.cic_inlk.gain * np.abs(self.rx.gain) / 4

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

    def encode_phase(self, phs: float, deg=True, width=19):
        """Convert phase value to register
        """
        scale = 360 if deg else (2 * np.pi)
        return int(phs / scale * 2**width)

    def decode_phase(self, phs_cnt, width=19, deg=True):
        """Convert phase value from register
        """
        scale = 360 if deg else (2 * np.pi)
        return wrap_phase(phs_cnt / 2**width * scale)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("-c", "--conf", default="LEMP",
                        help="Configuration key in settings.json")
    parser.add_argument("-f", "--settings_fname", default="settings.json",
                        help="Path to settings.json file")
    parser.add_argument("-o", "--output_fname",
                        default="llrf_shell_init_regs.json",
                        help="Path to output initialization json file")
    args = parser.parse_args()

    llrf_model = LLRFModel(conf=args.conf, settings_fname=args.settings_fname)
    with open(args.output_fname, 'w') as f:
        json.dump(llrf_model.init_config.__dict__, f, indent=4)
    pprint.pp(llrf_model.init_config)
    pprint.pp(llrf_model.cal_config)
    print(f"{args.output_fname} wrote with configuration: {args.conf}")
