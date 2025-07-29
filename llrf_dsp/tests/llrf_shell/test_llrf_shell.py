import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from llrf_model.llrf_dsp import LLRFModel, clamp
from local_bus import LocalbusAppMaster
import logging
import itertools
import numpy as np
from dataclasses import asdict
from pprint import pformat


class TB:
    def __init__(self, dut, f_config='USPAS', settings_fname='settings.json'):
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
        self.phs_exp = 0
        cocotb.start_soon(self.drive_adc(0, self.amp_exp, self.phs_exp))
        # cocotb.start_soon(self.drive_adc(1, self.amp_exp, self.phs_exp))

    def log_banner(self, str):
        self.dut._log.warning('*'*20 + f"{str:^20s}" + '*'*20)

    async def drive_adc(self, ch=0, amp=0, phs=0, noise_amp=3):
        for t in itertools.count():
            sig = amp * np.exp(1j * (self.llrf.omega * t + np.deg2rad(phs)))
            noise = random.randint(-noise_amp, noise_amp)
            await RisingEdge(self.dut.dsp_clk)
            self.dut.adc_array_in[ch].value = \
                clamp(int(sig.real + noise), -32768, 32767)

    async def init_test(self):
        await self.lb.write_reg('dsp_reset', 1)
        for name, reg in asdict(self.llrf.init_config).items():
            await self.lb.write_reg(name, reg)
        await self.lb.write_reg('dsp_reset', 0)

    async def test(self, wait=350):
        await self.init_test()
        for name, reg in asdict(self.llrf.init_config).items():
            value = await self.lb.read_reg(name)
            assert value == reg, f"Expected {name}:{reg}, got {value}"

        test_regs = {
            'amp_setpoint': self.amp_exp,
            'phs_setpoint': self.phs_exp,
            'circle_buf_flip': 1,
            'sig_buf_flip': 1,
        }
        for name, reg in test_regs.items():
            await self.lb.write_reg(name, reg)

        # wait for circle buffer ready
        await ClockCycles(self.dut.dsp_clk, wait)
        llrf_circle_ready = await self.lb.read_reg('llrf_circle_ready')
        assert llrf_circle_ready == 1, \
            f"Circle buffer not ready, got {llrf_circle_ready}"


@cocotb.test(timeout_time=15, timeout_unit='us')
async def test(dut):
    tb = TB(dut)
    await tb.test()
