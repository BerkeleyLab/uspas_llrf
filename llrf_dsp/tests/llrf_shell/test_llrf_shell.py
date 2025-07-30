import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from llrf_model.llrf_dsp import LLRFModel, clamp, wrap_phase
from local_bus import LocalbusAppMaster
import logging
import itertools
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
        self.dut._log.info(f'Calibrations:\n{pformat(llrf.cal_config)}')
        # clocks
        cocotb.start_soon(Clock(dut.lb_clk, 8, units="ns").start())
        cocotb.start_soon(Clock(dut.gtx_rxclk, 8, units="ns").start())
        cocotb.start_soon(
            Clock(dut.dsp_clk, llrf.DSP_CLK_CYCLE, units="ns").start())
        # inputs
        self.amp_exp = 10000
        self.phs_exp = -5
        # testbench setup
        self.llrf.init_config.chan_keep = 1 << llrf.MO_ADC
        self.circ_n_chan = bin(self.llrf.init_config.chan_keep).count('1')
        self.llrf.init_config.amp_setpoint = self.amp_exp
        self.llrf.init_config.phs_setpoint = self.phs_exp
        cocotb.start_soon(
            self.drive_adc(llrf.MO_ADC, self.amp_exp, self.phs_exp))

    def log_banner(self, str):
        self.dut._log.warning('*'*20 + f"{str:^20s}" + '*'*20)

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
        for t in itertools.count():
            sig = amp * np.exp(1j * (self.llrf.omega * t + np.deg2rad(phs)))
            noise = random.randint(-noise_amp, noise_amp)
            await RisingEdge(self.dut.dsp_clk)
            self.dut.adc_array_in[ch].value = \
                clamp(int(sig.real + noise), -32768, 32767)

    async def read_inlk_task(self, chan=0):
        """Read inlk amplitude and phase from the local bus.
        Args:
            chan: Channel to read, 0 for MO_ADC.
        Returns:
            complex value of reconstructed signal at the given index.
        """
        amp = await self.lb.read_reg('mon_amp', chan)
        phs = await self.lb.read_reg('mon_phs', chan)
        phs = wrap_phase(phs / 2**17 * np.pi * 2, deg=False)
        return amp * np.exp(1j * phs)

    async def read_waveform_task(self, index=0, chan=0):
        """Read one sample of waveform data at index from the circle buffer.
        Args:
            index: Waveform index of the sample to read,
            chan:  channel offset within chan_keep.
        Returns:
            complex value of reconstructed signal at the given index.
        """
        await self.lb.write_reg('circle_buf_flip', 1)
        # wait for circle buffer ready, rely on timeout_time for exceptions
        await RisingEdge(self.dut.llrf_shell.cbuf_transferred)
        assert await self.lb.read_reg('llrf_circle_ready')
        offset = self.circ_n_chan * index * 2  # 2 for I/Q
        i = await self.lb.read_reg('circle_data', offset + chan * 2)
        q = await self.lb.read_reg('circle_data', offset + chan * 2 + 1)
        return i + 1j * q

    async def init_test(self):
        await self.lb.write_reg('dsp_reset', 1)
        for name, reg in asdict(self.llrf.init_config).items():
            await self.lb.write_reg(name, reg)
        await self.lb.write_reg('dsp_reset', 0)

    async def test(self):
        await self.init_test()
        for name, reg in asdict(self.llrf.init_config).items():
            value = await self.lb.read_reg(name)
            assert value == reg, f"Expected {name}:{reg}, got {value}"

        inlk_meas = await self.read_inlk_task(self.llrf.MO_ADC)
        self.check_sig(inlk_meas / self.llrf.inlk_gain)
        await self.read_waveform_task()  # discard 1st waveform
        mon_mo_meas = await self.read_waveform_task(0, 0)
        self.check_sig(mon_mo_meas / self.llrf.mon_gain)


@cocotb.test(timeout_time=30, timeout_unit='us')
async def test(dut):
    tb = TB(dut)
    await tb.test()
