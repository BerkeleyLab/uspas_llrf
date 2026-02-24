from dataclasses import dataclass, field
import numpy as np
from uspas_llrf import dsp_config, to_signed, wrap_phase
from uspas_llrf import LLRFModule, RX, TX


class LLRF_DSP(LLRFModule):
    def __init__(self, config=dsp_config['USPAS']):
        """Math model that represents `llrf_dsp.v` to include DDC, DUC
        and feedback controller in `dsp_core.v`.
        See cocotb simulation in `test_llrf_dsp.py`.

        Args:
            dsp_config (str): Application configuration key (aka FSET),
              in ['LEMP', 'ALSU', 'USPAS', 'AWA']
        """
        for k, v in config.items():
            setattr(self, k, v)
        self.config = config
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
        self.tx = TX(
            num=self.TX_NUM_DDS, den=self.TX_DEN_DDS,
            dds_amp=self.LO_AMP, upsample=False)
        self.tx.add_tx_cordic(-np.angle(self.tx.gain, deg=True))
        self.submodules += self.rx.submodules
        self.submodules += self.tx.submodules

    @property
    def cal_factors(self):
        return self.LLRFCalibrations(
            rx_gain=np.abs(self.rx.gain),
            tx_gain=np.abs(self.tx.gain),
            rx_phase_off_deg=self.rx.cordic.phase_shift_deg,
            tx_phase_off_deg=self.tx.cordic.phase_shift_deg,
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
        amp_setpoint = int(amp_setpoint_adc / np.abs(self.tx.gain))
        phs_setpoint = int(phs_setpoint_deg / 360 * (1 << 18))
        max = int(self.cal_factors.max_amp_setpoint)
        assert amp_setpoint < max, \
            f"amp_setpoint: {amp_setpoint} > {max}!"
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
        amp_setpoint = int(amp_setpoint_adc * np.abs(self.rx.gain))
        phs_setpoint = int(phs_setpoint_deg / 360 * (1 << 18))
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
