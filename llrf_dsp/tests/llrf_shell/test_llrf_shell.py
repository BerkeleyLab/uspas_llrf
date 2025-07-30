import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from llrf_model.llrf_dsp import LLRFModel, clamp, wrap_phase
from local_bus import LocalbusAppMaster
import logging
import numpy as np
from dataclasses import asdict
from pprint import pformat


class TB:
    def __init__(self, dut, f_config='LEMP', settings_fname='settings.json'):
        dut._log.setLevel(logging.INFO)
        self.dut = dut
        self.llrf = llrf = LLRFModel(f_config, settings_fname)
        self.lb = LocalbusAppMaster(
            dut, dut.lb_clk, regmap_json_path='../../llrf_shell.json')
        self.log_banner(f'Simulating: {f_config}')
        self.dut._log.debug(f'Init registers:\n{pformat(llrf.init_config)}')
        self.dut._log.info(f'LLRF Model:\n{llrf.rx}')
        self.dut._log.info(f'Calibrations:\n{pformat(llrf.cal_config)}')
        # clocks
        cocotb.start_soon(Clock(dut.lb_clk, 8, units="ns").start())
        cocotb.start_soon(Clock(dut.gtx_rxclk, 8, units="ns").start())
        cocotb.start_soon(
            Clock(dut.dsp_clk, llrf.DSP_CLK_CYCLE, units="ns").start())

        # test bench setup
        self.loopback_dac, self.loopback_adc, self.test_adc = 0, 0, llrf.MO_ADC
        self.amp_exp = int(llrf.cal_config.max_adc_input)
        self.phs_exp = random.randint(-180, 180)
        cocotb.start_soon(
            self.drive_adc(self.test_adc, self.amp_exp, self.phs_exp))
        cocotb.start_soon(
            self.loopback(self.loopback_dac, self.loopback_adc))

    def log_banner(self, str):
        self.dut._log.info('*'*20 + f"{str:^20s}" + '*'*20)

    def check_sig(self, sig_meas):
        """Check the measured signal against expected amplitude and phase."""
        amp_meas = np.abs(sig_meas)
        phs_meas = np.angle(sig_meas, deg=True)
        self.dut._log.warning(
            f"expected mag: {self.amp_exp:8.2f} cnt,  "
            f"phs: {self.phs_exp:6.3f} deg")
        self.dut._log.warning(
            f"measured mag: {amp_meas:8.2f} cnt,  "
            f"phs: {phs_meas:6.3f} deg")
        amp_err = abs(amp_meas - self.amp_exp) / self.amp_exp
        assert amp_err < 0.001, "amplitude out-of-bound of 0.1%"
        phs_err = abs(wrap_phase(phs_meas - self.phs_exp))
        assert phs_err < 0.1, "phase out-of-bound of 0.1 deg"

    async def drive_adc(self, ch=0, amp=0, phs=0, noise_amp=3):
        t = 0
        while True:
            await RisingEdge(self.dut.dsp_clk)
            # truly important but empirical to synchronize with DDS
            if self.dut.llrf_shell.dsp_reset.value == 1:
                t = self.llrf.CIC_BASE_PERIOD % 15
            else:
                t += 1
            sig = amp * np.exp(1j * (self.llrf.omega * t + np.deg2rad(phs)))
            noise = random.randint(-noise_amp, noise_amp)
            self.dut.adc_array_in[ch].value = \
                clamp(int(sig.real + noise), -32768, 32767)

    async def loopback(self, dac_chan=0, adc_chan=0):
        while True:
            await RisingEdge(self.dut.dsp_clk)
            self.dut.adc_array_in[adc_chan].setimmediatevalue(
                self.dut.dac_array_out[dac_chan].value.signed_integer)

    async def read_inlk_task(self, chan=0):
        """Read inlk amplitude and phase from the local bus. """
        amp = await self.lb.read_reg('mon_amp', chan)
        phs = await self.lb.read_reg('mon_phs', chan)
        phs = wrap_phase(phs / 2**17 * np.pi * 2, deg=False)
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
        await RisingEdge(self.dut.llrf_shell.sig_buf_iq_transferred[0])
        assert await self.lb.read_reg('sig_buf_ready')
        wfm = []
        for idx in range(1 << self.dut.SIG_BUF_AW.value):
            s = await self.lb.read_reg(name, idx)
            wfm.append(s)
        return np.array(wfm)

    async def init_test(self):
        self.llrf.init_config.chan_keep = \
            (1 << self.test_adc | 1 << self.loopback_adc)
        self.cic_n_chan = bin(self.llrf.init_config.chan_keep).count('1')
        amp_setp, phs_setp = self.llrf.calc_open_loop_setp(
            self.amp_exp, self.phs_exp)
        self.llrf.init_config.amp_setpoint = amp_setp
        self.llrf.init_config.phs_setpoint = phs_setp
        self.llrf.init_config.dac_permit = True
        await self.lb.write_reg('dsp_reset', 1)
        for name, val in asdict(self.llrf.init_config).items():
            await self.lb.write_reg(name, val)
        await self.lb.write_reg('dsp_reset', 0)

    async def test(self):
        await self.init_test()
        self.log_banner('Init Registers')
        for name, val in asdict(self.llrf.init_config).items():
            r = await self.lb.read_reg(name)
            assert r == val, f"Expected {name}:{val}, got {r}"

        await self.read_cic_waveform()  # discard 1st waveform
        self.log_banner('CIC Waveform')
        for i in range(self.cic_n_chan):
            cic_meas = await self.read_cic_waveform(i)
            self.check_sig(cic_meas / self.llrf.mon_gain)

        self.log_banner('IQ Waveform')
        i_buf = await self.read_sig_buf(f'adc{self.test_adc}_i_buf')
        q_buf = await self.read_sig_buf(f'adc{self.test_adc}_q_buf')
        iq_avg = np.mean(i_buf + 1j * q_buf)
        gain = self.llrf.cal_config.rx_gain / self.llrf.CORDIC_GAIN
        self.check_sig(iq_avg / gain)

        self.log_banner('Interlock Waveform')
        inlk_meas = await self.read_inlk_task(self.test_adc)
        self.check_sig(inlk_meas / self.llrf.inlk_gain)


@cocotb.test(timeout_time=50, timeout_unit='us')
async def test(dut):
    tb = TB(dut)
    await tb.test()
