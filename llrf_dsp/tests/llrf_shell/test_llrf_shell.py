import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles
from llrf_model.llrf_dsp import LLRFModel, clamp, wrap_phase
from local_bus import LocalbusAppMaster
import logging
import numpy as np
from dataclasses import asdict
from pprint import pformat
import json
import itertools
import os


class TB:
    def __init__(self, dut, conf='LEMP', wave_samp_per=1):
        dut._log.setLevel(logging.INFO)
        self.dut = dut
        self.conf = conf
        with open('../../settings.json') as f:
            configs = json.load(f)
        dsp_config = configs[conf]
        # override tx dds setting for loopback test at IF_adc
        dsp_config['TX_NUM_DDS'] = dsp_config['NUM_DDS']
        dsp_config['TX_DEN_DDS'] = dsp_config['DEN_DDS'] * 2
        self.llrf = llrf = LLRFModel(dsp_config, wave_samp_per=wave_samp_per)
        self.lb = LocalbusAppMaster(
            dut, dut.lb_clk, regmap_json_path='../../llrf_shell.json')
        self.log_banner(f'Simulating: {conf}')
        self.dut._log.info(f'LLRF RX:\n{llrf.rx}')
        self.dut._log.info(f'LLRF TX:\n{llrf.tx}')
        self.dut._log.info(f'Calibrations:\n{pformat(llrf.cal_factors)}')

        # clocks
        cocotb.start_soon(Clock(dut.lb_clk, 8, units="ns").start())
        cocotb.start_soon(Clock(dut.gtx_rxclk, 8, units="ns").start())
        cocotb.start_soon(
            Clock(dut.dsp_clk, llrf.DSP_CLK_CYCLE, units="ns").start())
        cocotb.start_soon(
            Clock(dut.dac_clk, llrf.DSP_CLK_CYCLE / 2, units="ns").start())

        # test bench setup
        self.loopback_dac, self.feedback_dac = 0, 1
        self.feedback_adc = self.llrf.feedback_adc
        self.phaseref_adc = self.llrf.phaseref_adc
        # pick a random available ADC channel for loopback test
        available_adcs = [
            ch for ch in range(8)
            if ch not in [self.phaseref_adc, self.feedback_adc]]
        self.loopback_adc = random.choice(available_adcs)
        self.dut._log.warning(
            f'phaseref_adc: {self.phaseref_adc}, '
            f'loopback_adc: {self.loopback_adc}')
        # flattened signal array of 2 DAC + 8 ADC
        self.sig_names = {
            8 + self.feedback_dac: 'feedback_dac',
            8 + self.loopback_dac: 'loopback_dac',
            self.loopback_adc: 'loopback_adc',
            self.feedback_adc: 'feedback_adc',
            self.phaseref_adc: 'phaseref_adc'}

        self.amp_exp = int(llrf.cal_factors.max_adc_input)
        self.phs_exp = random.randint(-180, 180)
        cocotb.start_soon(
            self.drive_phaseref_adc(
                self.phaseref_adc, self.amp_exp, self.phs_exp))
        cocotb.start_soon(
            self.loopback(self.loopback_dac, self.loopback_adc))
        cocotb.start_soon(
            self.loopback(self.feedback_dac, self.feedback_adc))

    def log_banner(self, str):
        self.dut._log.info('*'*20 + f"{str:^20s}" + '*'*20)

    def check_sig(self, sig_meas, sig_name='signal'):
        """Check the measured signal against expected amplitude and phase."""
        amp_meas = np.abs(sig_meas)
        phs_meas = np.angle(sig_meas, deg=True)
        self.dut._log.warning(
            f"expected {sig_name:12s} mag: {self.amp_exp:8.2f} cnt,  "
            f"phs: {self.phs_exp:6.3f} deg")
        self.dut._log.warning(
            f"measured {sig_name:12s} mag: {amp_meas:8.2f} cnt,  "
            f"phs: {phs_meas:6.3f} deg")
        amp_err = abs(amp_meas - self.amp_exp) / self.amp_exp
        assert amp_err < 0.001, "amplitude out-of-bound of 0.1%"
        phs_err = abs(wrap_phase(phs_meas - self.phs_exp))
        assert phs_err < 0.1, "phase out-of-bound of 0.1 deg"

    async def drive_phaseref_adc(self, ch=0, amp=0, phs=0, noise_amp=3):
        await FallingEdge(self.dut.llrf_shell.dsp_reset)
        # truly important but empirical to synchronize with DDS
        t_start = {'ALSU': 0, 'USPAS': 1, 'LEMP': 6, 'AWA': 11}
        for t in itertools.count(t_start[self.conf]):
            await RisingEdge(self.dut.dsp_clk)
            sig = amp * np.exp(1j * (self.llrf.omega * t + np.deg2rad(phs)))
            noise = random.randint(-noise_amp, noise_amp)
            self.dut.adc_array_in[ch].value = \
                clamp(int(sig.real + noise), -32768, 32767)

    async def loopback(self, dac_chan=0, adc_chan=0):
        """ loopback dac_chan -> adc_chan with 1 cycle of latency """
        while True:
            await RisingEdge(self.dut.dsp_clk)
            self.dut.adc_array_in[adc_chan].value = \
                self.dut.dac_array_out[dac_chan].value

    async def read_inlk_task(self, chan=0):
        """Read inlk amplitude and phase from the local bus. """
        amp = await self.lb.read_reg('mon_amp', chan)
        phs = await self.lb.read_reg('mon_phs', chan)
        phs = self.llrf.decode_phase(phs, width=17, deg=False)
        return amp * np.exp(1j * phs)

    async def read_cic_waveform(self, chan=0):
        """Read average of waveform data from the circle buffer. """
        await self.lb.write_reg('circle_buf_flip', 1)
        # wait for circle buffer ready, rely on timeout_time for exceptions
        await RisingEdge(self.dut.llrf_shell.cbuf_transferred)
        assert await self.lb.read_reg('llrf_circle_ready')
        wfm = []
        for idx in range(1 << self.dut.CBUF_AW.value):
            offset = self.cic_n_chan * idx * 2  # 2 for I/Q
            i = await self.lb.read_reg('circle_data', offset + chan * 2)
            q = await self.lb.read_reg('circle_data', offset + chan * 2 + 1)
            wfm.append(i + 1j * q)
        return np.array(wfm, dtype=np.complex64).mean()

    async def read_sig_buf(self, name='adc0_buf'):
        await self.lb.write_reg('sig_buf_flip', 1)
        await RisingEdge(self.dut.llrf_shell.slow_snap)
        assert await self.lb.read_reg('sig_buf_ready')
        wfm = []
        for idx in range(1 << self.dut.SIG_BUF_AW.value):
            s = await self.lb.read_reg(name, idx)
            wfm.append(s)
        return np.array(wfm)

    async def read_adc_min_max(self, chan=0):
        await self.lb.write_reg('sig_buf_flip', 1)
        await RisingEdge(self.dut.llrf_shell.slow_snap)
        assert await self.lb.read_reg('sig_buf_ready')
        min = await self.lb.read_reg('dsp_slow_adc_min', chan)
        max = await self.lb.read_reg('dsp_slow_adc_max', chan)
        return min, max

    async def write_init_regs(self):
        self.dut._log.info(f'InitRegisters:\n{pformat(self.llrf.init_regs)}')
        for name, val in asdict(self.llrf.init_regs).items():
            await self.lb.write_reg(name, val)
        # single cycle, for resetting both up/down DDS
        await self.lb.write_reg('dsp_reset', 1)

    async def verify_init_regs(self):
        for name, val in asdict(self.llrf.init_regs).items():
            r = await self.lb.read_reg(name)
            assert r == val, f"Expected {name}:{val}, got {r}"

    async def test_open_loop(self):
        self.llrf.init_regs.chan_keep = \
            (1 << self.phaseref_adc | 1 << self.loopback_adc)
        self.cic_chans = [
            int(b) for b in f'{self.llrf.init_regs.chan_keep:010b}']
        self.cic_n_chan = self.cic_chans.count(1)
        self.cic_names = [
            self.sig_names[9-idx] for idx, enabled in enumerate(self.cic_chans)
            if enabled][::-1]  # lsb_mask==1: first chan is LSB
        self.dut._log.debug(f'cic chans: {self.cic_chans}')
        self.dut._log.debug(f'cic names: {self.cic_names}')
        self.llrf.init_regs.dac_permit = True
        # compensate for 1 cycle latency of loopback
        phs_exp1 = wrap_phase(self.phs_exp + np.rad2deg(self.llrf.omega))
        amp_setp, phs_setp = self.llrf.calc_open_loop_setp(
            self.amp_exp, phs_exp1)
        self.llrf.init_regs.amp_setpoint = amp_setp
        self.llrf.init_regs.phs_setpoint = phs_setp
        await self.write_init_regs()
        self.log_banner('Open Loop Test')
        await self.verify_init_regs()

        await self.read_cic_waveform()  # discard 1st waveform
        self.log_banner('CIC Waveform')
        for i, name in enumerate(self.cic_names):
            cic_meas = await self.read_cic_waveform(i)
            self.check_sig(cic_meas / self.llrf.mon_gain, sig_name=name)

        self.log_banner('IQ Waveform')
        i_buf = await self.read_sig_buf(f'adc{self.phaseref_adc}_i_buf')
        q_buf = await self.read_sig_buf(f'adc{self.phaseref_adc}_q_buf')
        iq_avg = np.mean(i_buf + 1j * q_buf)
        gain = self.llrf.cal_factors.rx_gain / self.llrf.CORDIC_GAIN
        self.check_sig(iq_avg / gain, sig_name='phaseref_adc')

        self.log_banner('Min / Max')
        for chan in [self.phaseref_adc, self.loopback_adc]:
            min, max = await self.read_adc_min_max(chan)
            assert abs(-self.amp_exp - min) / self.amp_exp < 0.1, \
                "ADC min out of range"
            assert abs(self.amp_exp - max) / self.amp_exp < 0.1, \
                "ADC min out of range"
            self.dut._log.warning(
                f"measured {self.sig_names[chan]:12s} min: {min:8.2f} cnt,  "
                f"max: {max:6.2f} cnt")

        self.log_banner('Interlock')
        for chan in [self.phaseref_adc, self.loopback_adc]:
            inlk_meas = await self.read_inlk_task(chan)
            self.check_sig(inlk_meas / self.llrf.inlk_gain,
                           sig_name=self.sig_names[chan])

    async def test_close_loop(self, wait=2000):
        self.log_banner('Close Loop Test')
        amp_setp, phs_setp = self.llrf.calc_close_loop_setp(
            self.amp_exp, self.phs_exp)
        self.llrf.init_regs.amp_setpoint = amp_setp
        self.llrf.init_regs.phs_setpoint = phs_setp
        self.llrf.init_regs.Kp_amp = 2000
        self.llrf.init_regs.Kp_phs = 5000
        self.llrf.init_regs.Ki_amp = 100
        self.llrf.init_regs.Ki_phs = 500
        await self.write_init_regs()
        regs = [
            ('amp_loop_reset', 1),
            ('phs_loop_reset', 1),
            ('amp_loop_enable', 1),
            ('phs_loop_enable', 1),
            ('amp_loop_reset', 0),
            ('phs_loop_reset', 0),
        ]
        for name, val in regs:
            await self.lb.write_reg(name, val)
        await ClockCycles(self.dut.dsp_clk, wait)  # settling time of loops
        inlk_meas = await self.read_inlk_task(self.feedback_adc)
        self.check_sig(inlk_meas / self.llrf.inlk_gain,
                       sig_name='feedback_adc')

    async def test_fast_interlock(self, wait=30):
        self.log_banner('Fast Interlock Test')
        amp_lo = self.amp_exp * self.llrf.inlk_gain * 0.99
        amp_hi = self.amp_exp * self.llrf.inlk_gain * 1.01
        regs = [
            ('inlk_inlk_mode', self.phaseref_adc, 0b10),
            ('inlk_amp_lo', self.phaseref_adc, amp_lo),
            ('inlk_amp_hi', self.phaseref_adc, amp_hi),
        ]
        for name, offset, val in regs:
            await self.lb.write_reg(name, val, offset)
        await ClockCycles(self.dut.dsp_clk, wait)  # wait for setting
        await self.lb.write_reg('inlk_permit_mask', 1 << self.phaseref_adc)
        await self.lb.write_reg('inlk_reset_inlk', 1)

        dut = self.dut.llrf_shell
        await RisingEdge(dut.inlk_permit_out)  # wait for inlk permit to reset
        await RisingEdge(dut.inlk.wave_valid)
        self.dut._log.info("%8s " * 9 % (
            'chan', 'mon_amp', 'amp_lo', 'amp_hi', '>=lo', '>=hi',
            'permit', 'amp', 'phs'))
        for _ in range(20):
            await RisingEdge(self.dut.dsp_clk)
            mon_addr = dut.mon_addr_out.value.integer
            mon_amp_out = dut.mon_amp_out.value.signed_integer
            mon_phs_cnt = dut.mon_phs_out.value.signed_integer
            mon_phs_out = self.llrf.decode_phase(mon_phs_cnt, width=17)
            amp_valid = dut.inlk.wave_cnt.value % 2 == 1
            if dut.inlk.wave_valid and amp_valid:
                self.dut._log.info(
                    f"{mon_addr:8d} "
                    f"{mon_amp_out:8d} "
                    f"{dut.inlk.amp_lo.value.integer:8d} "
                    f"{dut.inlk.amp_hi.value.integer:8d} "
                    f"{dut.inlk.cmpg_lo.value.integer:8d} "
                    f"{dut.inlk.cmpg_hi.value.integer:8d} "
                    f"{dut.inlk_permit_out.value.integer:8d} "
                    f"{mon_amp_out / self.llrf.inlk_gain:8.1f} "
                    f"{mon_phs_out:8.1f} ")
        assert dut.inlk_permit_out.value == 1

    async def test_trigger(self):
        await self.lb.write_reg('wave_trig_sel', 1)
        pass


@cocotb.test(timeout_time=400, timeout_unit='us')
async def test(dut):
    tb = TB(dut,
            conf=os.getenv('FSET', 'LEMP'),  # XXX
            wave_samp_per=random.randint(1, 8))
    await tb.test_open_loop()
    await tb.test_fast_interlock()
    await tb.test_close_loop()
