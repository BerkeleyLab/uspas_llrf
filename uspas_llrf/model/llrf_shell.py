import argparse
import pprint
import numpy as np
import json
from uspas_llrf import dsp_config, CICWaveRecorder, RX, TX, LLRF_DSP
from uspas_llrf import regmap
from uspas_llrf.regmap import WaveTrigSel, DacDriveSel, InlkFaultMode  # noqa: F401


class LLRFShell(LLRF_DSP):
    def __init__(self, dsp_config=dsp_config['USPAS'], wave_samp_per=1, design=None):
        """Represent DSP modules in llrf_shell.v, which include separate RX
        and TX DDS for digital down and up conversion, where the TX DUC is
        in dac_clk domain with interpolation (upsample). Also, CIC waveform
        and interlock data streams are included with gain properties.

        A set of registers are created for initialization during booting:
        the registers with an init value in uspas_llrf/regmap.py. Their
        values are generated based on DSP configuration and checked against
        the register widths.
        A json file is generated and converted into C source files for actual
        build.

        Behavioral simulation are performed using cocotb by writing through
        the control bus before verification in `test_llrf_shell.py`.
        Args:
            dsp_config (str): Application configuration key (aka FSET),
              in ['LEMP', 'ALSU', 'USPAS', 'AWA']
            wave_samp_per (int): CIC waveform decimation factor
            design (str): designs/<design> whose register map holds the
              boot-time registers (default: the base map)
        """
        self.wave_samp_per = wave_samp_per
        self.regs = regmap.load_design(regmap.design_file(design))
        self.LLRFInitRegisters = regmap.init_registers(self.regs)
        super().__init__(dsp_config)
        self.feedback_adc = self.config['LOOP0_ADC_CHAN']
        self.phaseref_adc = self.config['PRL_ADC_CHAN']

    def init_modules(self):
        """ Assemble DSP modules """
        self.rx = RX(num=self.num, den=self.den, dds_amp=self.config['LO_AMP'])
        # compensate RX phase gain by rx.dds
        self.rx.dds.phase_shift_deg = -np.angle(self.rx.gain, deg=True)
        self.rx.add_rx_cordic()

        self.tx = TX(num=self.config['TX_NUM_DDS'], den=self.config['TX_DEN_DDS'],
                     dds_amp=self.config['LO_AMP'])
        self.tx.dds.phase_shift_deg = -np.angle(self.tx.gain, deg=True)
        # pre-compensate TX phase to match DAC IF phase, applied to tx_cordic
        # very tricky to understand!
        tx_phase_off_cycles = self.config['TX_DEN_DDS'] - self.CORDIC_NSTG
        self.tx.add_tx_cordic(
            -tx_phase_off_cycles * np.rad2deg(self.tx.omega))
        self.cic_inlk = CICWaveRecorder(
            num=self.num, den=self.den,
            cic_base_period=self.config['CIC_BASE_PERIOD'],
            shift_base=self.config['INLK_SHIFT_BASE'], shift_add=self.config['INLK_SHIFT_ADD'])
        self.cic_mon = CICWaveRecorder(
            num=self.num, den=self.den,
            cic_base_period=self.config['CIC_BASE_PERIOD'],
            shift_base=self.config['CIC_SHIFT_BASE'],
            wave_samp_per=self.wave_samp_per)
        self.submodules += self.rx.submodules
        self.submodules += self.tx.submodules
        self.gen_init_regs()

    def gen_init_regs(self, int_trig_rate_hz=20):
        """ initialization registers for simulation and SoC integration
            cic and inlk wave_shift values are derived from gain calculations
        """
        int_trig_period = self.config['DEN_DDS'] * \
            round(1e9 / self.config['DSP_CLK_CYCLE'] / self.config['DEN_DDS'] / int_trig_rate_hz)
        self.init_regs = self.LLRFInitRegisters(
            rx_dds_amplitude=self.rx.dds.amp,
            rx_dds_phase_shift=self.encode_phase(-self.rx.dds.phase_shift_deg),
            rx_dds_phase_step=self.rx.dds.phase_step,
            rx_dds_modulo=self.rx.dds.modulo,
            tx_dds_amplitude=self.tx.dds.amp,
            tx_dds_phase_shift=self.encode_phase(self.tx.dds.phase_shift_deg),
            tx_dds_phase_step=self.tx.dds.phase_step,
            tx_dds_modulo=self.tx.dds.modulo,
            duc_spectral_flip=self.config['TX_SECOND_NYQUIST'],
            rx_phase_offset=0,
            tx_phase_offset=self.encode_phase(-self.tx.cordic.phase_shift_deg),
            tx_afe_spectral_flip=self.config['TX_AFE_SPECTRAL_FLIP'],
            prl_adc_chan=self.config['PRL_ADC_CHAN'],
            loop0_adc_chan=self.config['LOOP0_ADC_CHAN'],
            loop1_adc_chan=self.config['LOOP1_ADC_CHAN'],
            wave_samp_per=self.wave_samp_per,
            cic_base_period=self.config['CIC_BASE_PERIOD'],
            cic_wave_shift=self.cic_mon.wave_shift,
            inlk_wave_shift=self.cic_inlk.wave_shift,
            chan_keep=0b11,
            loop0_Kp_amp=20, loop0_Ki_amp=50,
            loop0_Kp_phs=50, loop0_Ki_phs=200,
            loop0_max_amp_setpoint=int(self.cal_factors.max_amp_setpoint),
            loop1_Kp_amp=20, loop1_Ki_amp=50,
            loop1_Kp_phs=50, loop1_Ki_phs=200,
            loop1_max_amp_setpoint=int(self.cal_factors.max_amp_setpoint),
            loop0_pulse_start=0, loop0_pulse_high_len=10,
            loop1_pulse_start=0, loop1_pulse_high_len=10,
            dac_drive_sel=DacDriveSel(self.config['DAC_DRIVE_SEL']),
            drv0_pulse_mode=self.config['DRV0_PULSE_MODE'],
            drv1_pulse_mode=self.config['DRV1_PULSE_MODE'],
            # CW LLRF (USPAS, ALSU) diagnoses with cic_waves, so the slow
            # block snapshots on cbuf_transferred; pulsed LLRF (AWA, LEMP)
            # uses the IQ waveforms and snapshots on sig_buf transfer.
            slow_snap_cic=self.config['SLOW_SNAP_CIC'],
            int_trigger_period=int_trig_period,
            evcode=self.config['EVCODE']
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
            Ensure the gain is less than 1 to avoid saturation.
        """
        inlk_gain = self.cic_inlk.gain * self.rx.gain
        assert np.abs(inlk_gain) <= 1, f"inlk_gain {inlk_gain} > 1"
        return inlk_gain

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
            tx_phase_off_deg=self.tx.dds.phase_shift_deg,
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
    parser.add_argument("-c", "--conf", default="USPAS",
                        help="Configuration key in settings.json")
    parser.add_argument("-d", "--design", help="designs/<design> register map (default: base map)")
    parser.add_argument("--write-init-reg",
                        help="Path to write initialization registers json")
    parser.add_argument("--write-verilog-header",
                        help="Path to write verilog header")

    args = parser.parse_args()

    model = LLRFShell(dsp_config[args.conf], design=args.design)
    if args.write_init_reg:
        pprint.pp(model.init_regs)
        pprint.pp(model.cal_factors)
        with open(args.write_init_reg, 'w') as f:
            json.dump(model.init_regs.__dict__, f, indent=4)
        print(f"{args.write_init_reg} wrote with configuration: {args.conf}")
