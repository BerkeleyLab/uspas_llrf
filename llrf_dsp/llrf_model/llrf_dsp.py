import numpy as np
import json
from dataclasses import dataclass, field
from pathlib import Path
from enum import IntEnum
import argparse
import pprint


with open(Path(__file__).resolve().parent.parent / 'settings.json') as f:
    default_configs = json.load(f)


def wrap_phase(phs: float, deg=True):
    """Wrap phase value to be within [-180, 180] or [-pi, pi].
    """
    scale = 180 if deg else np.pi
    return (phs + scale) % (2 * scale) - scale


def clip_int(value, n_bit=16):
    max_value = (1 << n_bit - 1) - 1
    min_value = -(1 << n_bit - 1)
    return max(min_value, min(int(value), max_value))


def to_signed(value: int, width: int = 18):
    """Converts an integer to the signed value from two's compliment format
        e.g. 0b1000 is -8
    """
    v = int(value)
    if v >= 2**(width - 1):
        return v - 2**width
    else:
        return v


class LLRFModule:
    # 1.646760258
    CORDIC_NSTG = 21  # cordic_g22.v: nstg=21
    CORDIC_LATENCY = CORDIC_NSTG + 1
    CORDIC_GAIN = np.prod([np.sqrt(1 + 4**-n) for n in range(CORDIC_NSTG)])

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
            self, amp: int = 74840, phase_shift_deg: float = 0,
            width: int = 18, num: int = 4,  den: int = 11) -> None:
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
        self.width = width
        self.phs_shift_width = width + 1
        self._amp = amp
        self._phase_shift_deg = phase_shift_deg
        self.update_gain()
        self.dwh = dwh = 20  # high part of phase step
        self.dwl = dwl = 32 - self.dwh  # low part of phase step
        self.phase_step_h, self.phase_step_l, self.modulo = \
            self.calc_dds_config(dwh, dwl)
        self.phase_step = (self.phase_step_h << dwl) | self.phase_step_l

    @property
    def full_scale_amp(self) -> int:
        return (1 << self.width - 1) / self.CORDIC_GAIN

    @property
    def amp(self) -> int:
        return self._amp

    @amp.setter
    def amp(self, val: int) -> None:
        self._amp = int(val)
        self.update_gain()

    @property
    def phase_shift_deg(self) -> int:
        return self._phase_shift_deg

    @phase_shift_deg.setter
    def phase_shift_deg(self, val: float) -> None:
        self._phase_shift_deg = val
        self.update_gain()

    def update_gain(self):
        self.gain = self._amp / self.full_scale_amp * \
            np.exp(1j * np.deg2rad(self._phase_shift_deg))
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

    def encode_phase(self, phs, deg=True):
        scale = 360 if deg else (2 * np.pi)
        p = wrap_phase(phs, deg) / scale * 2**(self.phs_shift_width)
        return to_signed(p, width=self.phs_shift_width)


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
                 phase_shift_deg: float = 0) -> None:
        """Receiver or Transceiver CORDIC.
            Gateware: cordicg_b22.v (rx_cordic or tx_cordic).

        Args:
            num (int): numerator of IF / Fs. Defaults to 4.
            den (int): denominator of IF / Fs. Defaults to 11.
            phase_shift_deg (float): Phase offset in degrees.
        """
        super().__init__(num, den)
        self._phase_shift_deg = phase_shift_deg
        self.update_gain()

    @property
    def phase_shift_deg(self) -> int:
        return self._phase_shift_deg

    @phase_shift_deg.setter
    def phase_shift_deg(self, val: float) -> None:
        self._phase_shift_deg = val
        self.update_gain()

    def update_gain(self):
        self.gain = self.CORDIC_GAIN * \
            np.exp(1j * np.deg2rad(self._phase_shift_deg))


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
        self._wave_shift = int(max((full_shift - self.shift_base), 0))
        self._gain = 2**(cic_bit_growth - self.shift_base - self._wave_shift)

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


class RX(LLRFModule):
    def __init__(self, num: int = 4, den: int = 11,
                 dds_amp=74840) -> None:
        """ Receiver DSP chain.
            Gateware: ddc.v, dds.v

        Args:
            num (int): numerator of IF / Fs. Defaults to 4.
            den (int): denominator of IF / Fs. Defaults to 11.
            dds (DDS): external dds.
        """
        super().__init__(num, den)
        self.dds = DDS(amp=dds_amp, num=num, den=den)
        self.submodules += [
            WashoutFilter(num=num, den=den),
            self.dds,
            DDC(num=num, den=den)]

    def add_rx_cordic(self, phase_shift_deg=0):
        """ Include rx_cordic in dsp_core.v,
            with compensation for phase gain of upstream modules
        """
        self.cordic = CORDIC(
            num=self.num, den=self.den, phase_shift_deg=phase_shift_deg)
        self.submodules += [self.cordic]


class DUC(LLRFModule):
    def __init__(self, num: int = 4,  den: int = 11, upsample: bool = True):
        """Non-IQ Digital Up-Conversion.
            Gateware:
            upsample = False:
                cpxmul_fullspeed.v with pipeline=3
            upsample = True:
                dac_duc.v with pipeline=8 + 3

        Args:
            num (int): numerator of IF / Fs. Defaults to 4.
            den (int): denominator of IF / Fs. Defaults to 11.
        """
        super().__init__(num, den)
        self.pipeline = 11 if upsample else 3
        self.gain = self.z**(-self.pipeline)


class DSPCoreTX(LLRFModule):
    def __init__(self, num: int = 4, den: int = 11,
                 dds_amp=74840,
                 has_cordic: bool = True,
                 upsample: bool = True,
                 dds: DDS = None) -> None:
        """Transmitter DSP chain.
            Gateware: tx_cordic.v, cpxmul_fullspeed.v or dac_duc.v

        Args:
            num (int): numerator of IF / Fs. Defaults to 4.
            den (int): denominator of IF / Fs. Defaults to 11.
            dds (DDS): external DDS.
        """
        super().__init__(num, den)
        if dds is None:
            dds = DDS(amp=dds_amp, num=num, den=den)
        self.dds = dds
        self.duc = duc = DUC(num=num, den=den, upsample=upsample)
        self.submodules += [dds, duc]
        if has_cordic:  # in dsp_core.v, in dsp_clk domain!
            self.phase_off_deg = np.angle(self.gain, deg=True)
            # compensate phase gain of upstream modules
            self.tx_cordic = CORDIC(
                num=num, den=den, phase_shift_deg=-self.phase_off_deg)
            self.submodules += [self.tx_cordic]


class LLRF_DSP(LLRFModule):
    def __init__(self, dsp_config=default_configs['USPAS']):
        """Math model that represents `llrf_dsp.v` to include DDC, DUC
        and feedback controller in `dsp_core.v`.
        See cocotb simulation in `test_llrf_dsp.py`.

        Args:
            dsp_config (str): Application configuration key (aka FSET),
              in ['LEMP', 'ALSU', 'USPAS', 'AWA']
        """
        for k, v in dsp_config.items():
            setattr(self, k, v)
        self.config = dsp_config
        super().__init__(self.NUM_DDS, self.DEN_DDS)
        self.init_modules()

    @dataclass
    class LLRFCalibrations:
        """Calibration configuration for LLRF DSP module."""
        rx_gain: float = 1.0  # ratio from ADC to controller
        tx_gain: float = 1.0  # ratio from controller to DAC
        rx_phase_off_deg: float = 0.0
        tx_phase_off_deg: float = 0.0
        rx_dds_omega_deg: float = 0.0  # num / den
        tx_dds_omega_deg: float = 0.0  # tx_num / tx_den
        cic_wfm_gain: float = 1.0
        inlk_gain: float = 1.0
        inlk_tx_gain: float = 1.0
        rx_iq_gain: float = 1.0
        tx_iq_gain: float = 1.0
        max_adc_input: float = (1 << 15) * 0.95  # absolute max ADC input level
        max_dac_drive: float = (1 << 15) * 0.95  # absolute max DAC drive level
        max_amp_setpoint: float = field(init=False)  # max amplitude setpoint

        def __post_init__(self):
            """Post-initialization to calculate dependent fields."""
            self.max_amp_setpoint = self.max_dac_drive / self.tx_gain

    def init_modules(self):
        """ Assemble DSP modules """
        self.rx = RX(
            num=self.num, den=self.den, dds_amp=self.LO_AMP)
        # compensate RX phase gain by rx_cordic
        self.rx.add_rx_cordic(-np.angle(self.rx.gain, deg=True))
        self.tx = DSPCoreTX(
            num=self.TX_NUM_DDS, den=self.TX_DEN_DDS,
            dds_amp=self.LO_AMP, upsample=False)
        self.submodules += self.rx.submodules
        self.submodules += self.tx.submodules

    @property
    def cal_factors(self):
        return self.LLRFCalibrations(
            rx_gain=np.abs(self.rx.gain),
            tx_gain=np.abs(self.tx.gain),
            rx_phase_off_deg=self.rx.cordic.phase_shift_deg,
            tx_phase_off_deg=self.tx.phase_off_deg,
            rx_dds_omega_deg=np.rad2deg(self.rx.dds.omega),
            tx_dds_omega_deg=np.rad2deg(self.tx.dds.omega)
        )

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
        return to_signed(amp_setpoint), to_signed(phs_setpoint)

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
        return to_signed(amp_setpoint), to_signed(phs_setpoint)

    def encode_phase(self, phs: float, width=19, deg=True):
        """Convert phase value to signed register
        """
        scale = 360 if deg else (2 * np.pi)
        wrapped_phase = wrap_phase(phs, deg) / scale * 2**width
        return to_signed(wrapped_phase, width=width)

    def decode_phase(self, phs_cnt: int, width=19, deg=True):
        """Convert phase value from register
        """
        scale = 360 if deg else (2 * np.pi)
        return wrap_phase(phs_cnt / 2**width * scale)


class WaveTrigSel(IntEnum):
    Internal = 0
    External = 1
    EVR = 3


class LLRFShell(LLRF_DSP):
    def __init__(self, dsp_config=default_configs['USPAS'], wave_samp_per=1):
        """Represent DSP modules in llrf_shell.v, which include separate RX
        and TX DDS for digital down and up conversion, where the TX DUC is
        in dac_clk domain with interpolation (upsample). Also, CIC waveform
        and interlock data streams are included with gain properties.

        A set of registers are created for initialization during booting.
        The value of these registers are generated based on DSP configuration.
        A json file is generated and converted into C source files for actual
        build.

        Behavioral simulation are performed using cocotb by writing through
        the control bus before verification in `test_llrf_shell.py`.
        Args:
            dsp_config (str): Application configuration key (aka FSET),
              in ['LEMP', 'ALSU', 'USPAS', 'AWA']
            wave_samp_per (int): CIC waveform decimation factor
        """
        self.wave_samp_per = wave_samp_per
        super().__init__(dsp_config)
        self.feedback_adc = self.FDBK_ADC_CHAN
        self.phaseref_adc = self.PRL_ADC_CHAN

    @classmethod
    def from_json(cls, conf='USPAS', json_fname="../settings.json",
                  wave_samp_per=1):
        """alternative constructor from json file loader"""
        with open(json_fname) as f:
            configs = json.load(f)
        return cls(configs[conf], wave_samp_per)

    @dataclass
    class LLRFInitRegisters:
        """Initial register configuration for LLRF DSP module."""
        dds_amplitude: int = 0
        dds_phase_step: int = 0
        dds_phase_shift: int = 0
        dds_modulo: int = 0
        tx_dds_amplitude: int = 0
        tx_dds_phase_step: int = 0
        tx_dds_phase_shift: int = 0
        tx_dds_modulo: int = 0
        duc_spectral_flip: bool = False
        wave_samp_per: int = 1
        cic_base_period: int = 14
        cic_wave_shift: int = 0
        inlk_wave_shift: int = 0
        chan_keep: int = 0
        rx_phase_offset: int = 0
        tx_phase_offset: int = 0
        amp_setpoint: int = 0
        phs_setpoint: int = 0
        amp_loop_enable: bool = False
        phs_loop_enable: bool = False
        amp_loop_reset: bool = False
        phs_loop_reset: bool = False
        Kp_amp: int = 0
        Ki_amp: int = 0
        Kp_phs: int = 0
        Ki_phs: int = 0
        pulse_mode: bool = False
        pulse_high_len: int = 10
        dac_permit: bool = False
        slow_snap_cic: bool = False
        prl_adc_chan: int = 0
        fdbk_adc_chan: int = 0
        wave_trig_sel: int = WaveTrigSel.Internal

        def __setattr__(self, name, value):
            """Enforce data type casting, e.g. int"""
            annotations = getattr(self, '__annotations__', {})
            if name in annotations:
                expected_type = annotations[name]
                if not isinstance(value, expected_type):
                    value = expected_type(value)
            super().__setattr__(name, value)

    def init_modules(self):
        """ Assemble DSP modules """
        # pre-compensate TX phase to match DAC IF phase, applied to tx_cordic
        # very tricky to understand!
        self.tx_phase_off_cycles = self.TX_DEN_DDS - self.CORDIC_NSTG
        self.rx = RX(
            num=self.num, den=self.den, dds_amp=self.LO_AMP)
        # compensate RX phase gain by rx.dds
        self.rx.dds.phase_shift_deg = -np.angle(self.rx.gain, deg=True)
        self.rx.add_rx_cordic()
        self.tx = DSPCoreTX(
            num=self.TX_NUM_DDS, den=self.TX_DEN_DDS,
            dds_amp=self.LO_AMP)
        self.tx.gain *= self.tx.z**(-self.tx_phase_off_cycles)
        self.cic_inlk = CICWaveRecorder(
            num=self.num, den=self.den,
            cic_base_period=self.CIC_BASE_PERIOD,
            shift_base=self.INLK_SHIFT_BASE)
        self.cic_mon = CICWaveRecorder(
            num=self.num, den=self.den,
            cic_base_period=self.CIC_BASE_PERIOD,
            shift_base=self.CIC_SHIFT_BASE,
            wave_samp_per=self.wave_samp_per)
        self.submodules += self.rx.submodules
        self.submodules += self.tx.submodules
        self.gen_init_regs()

    def gen_init_regs(self):
        """ initialization registers for simulation and SoC integration
            cic and inlk wave_shift values are derived from gain calculations
        """
        self.init_regs = self.LLRFInitRegisters(
            dds_amplitude=self.rx.dds.amp,
            dds_phase_shift=self.encode_phase(-self.rx.dds.phase_shift_deg),
            dds_phase_step=self.rx.dds.phase_step,
            dds_modulo=self.rx.dds.modulo,
            tx_dds_amplitude=self.tx.dds.amp,
            tx_dds_phase_shift=self.encode_phase(-self.tx.phase_off_deg),
            tx_dds_phase_step=self.tx.dds.phase_step,
            tx_dds_modulo=self.tx.dds.modulo,
            duc_spectral_flip=False,
            rx_phase_offset=0,
            tx_phase_offset=self.encode_phase(
                self.tx_phase_off_cycles * np.rad2deg(self.tx.omega)),
            prl_adc_chan=self.PRL_ADC_CHAN,
            fdbk_adc_chan=self.FDBK_ADC_CHAN,
            wave_samp_per=self.wave_samp_per,
            cic_base_period=self.CIC_BASE_PERIOD,
            cic_wave_shift=self.cic_mon.wave_shift,
            inlk_wave_shift=self.cic_inlk.wave_shift,
            chan_keep=0b11,
            Kp_amp=20, Ki_amp=50, Kp_phs=50, Ki_phs=200
        )

    @property
    def rx_iq_gain(self):
        """ Digital Down Conversion gain,
            from ADC to IQ pairs (e.g. ADC IQ waveforms)
        """
        return self.rx.gain / self.CORDIC_GAIN

    @property
    def tx_iq_gain(self):
        """ Digital Up Conversion gain,
            from IQ pairs to DAC (e.g. DAC IQ waveforms)
        """
        return self.tx.gain / self.CORDIC_GAIN

    @property
    def cic_wfm_gain(self):
        """ CIC waveform recorder gain for RX,
            from ADC to IQ pairs, including:
            * RX (DDC) gain (excluding CORDIC)
            * CIC wave recorder gain
        """
        return self.cic_mon.gain * self.rx_iq_gain

    @property
    def inlk_gain(self):
        """ Interlock IQ stream gain for RX,
            from ADC to mon_amp/mon_phs values,
            which include
              * RX (DDC) gain, including CORDIC in monitor_inlk.v
              * CIC filter (inlk) gain
        """
        return self.cic_inlk.gain * self.rx.gain

    @property
    def inlk_tx_gain(self):
        """ Interlock IQ stream gain for TX,
            from DAC to mon_amp/mon_phs values,
            which include:
              * CIC filter (inlk) gain
              * CORDIC in monitor_inlk.v
            Because baseband drive_i/drive_q are used for monitoring, the
            TX (DUC) gain needs to be considered when deriving DAC values.
            Also include pre-compensate by setpoint
        """
        return self.cic_inlk.gain * self.CORDIC_GAIN / self.tx_iq_gain

    @property
    def cal_factors(self):
        return self.LLRFCalibrations(
            rx_gain=np.abs(self.rx.gain),
            tx_gain=np.abs(self.tx.gain),
            rx_phase_off_deg=-self.rx.dds.phase_shift_deg,
            tx_phase_off_deg=self.tx.phase_off_deg,
            rx_dds_omega_deg=np.rad2deg(self.rx.dds.omega),
            tx_dds_omega_deg=np.rad2deg(self.tx.dds.omega),
            cic_wfm_gain=self.cic_wfm_gain,
            inlk_gain=self.inlk_gain,
            rx_iq_gain=self.rx_iq_gain,
            tx_iq_gain=self.tx_iq_gain,
            inlk_tx_gain=self.inlk_tx_gain
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("-c", "--conf", default="LEMP",
                        help="Configuration key in settings.json")
    parser.add_argument("-f", "--json_fname", default="../settings.json",
                        help="Path to settings.json file")
    parser.add_argument("--write-init-reg",
                        help="Path to write initialization registers json")
    parser.add_argument("--write-verilog-header",
                        help="Path to write verilog header")

    args = parser.parse_args()

    llrf_model = LLRFShell.from_json(
        conf=args.conf, json_fname=args.json_fname)
    if args.write_init_reg:
        pprint.pp(llrf_model.init_regs)
        pprint.pp(llrf_model.cal_factors)
        with open(args.write_init_reg, 'w') as f:
            json.dump(llrf_model.init_regs.__dict__, f, indent=4)
        print(f"{args.write_init_reg} wrote with configuration: {args.conf}")

    if args.write_verilog_header:
        with open(args.write_verilog_header, 'w') as f:
            for k, v in llrf_model.config.items():
                # the only 2 macros still being used.
                # Others are in init registers
                if k in ['DSP_EV1', 'DSP_CLK_CYCLE']:
                    f.write(f"`define {k} {v}\n")
