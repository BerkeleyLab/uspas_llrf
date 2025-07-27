import cocotb
from cocotb.clock import Clock
from llrf_model.llrf_dsp import LLRFModel
import logging


class TB:
    def __init__(self, dut, f_config='USPAS', settings_fname='settings.json'):
        dut._log.setLevel(logging.INFO)
        self.dut = dut
        self.llrf = llrf = LLRFModel(f_config, settings_fname)
        cocotb.start_soon(Clock(dut.lb_clk, 8, units="ns").start())
        cocotb.start_soon(
            Clock(dut.dsp_clk, llrf.DSP_CLK_CYCLE, units="ns").start())

    def log_banner(self, str):
        self.dut._log.warning('*'*20 + f"{str:^20s}" + '*'*20)

    async def test(self, wait=200):
        pass


@cocotb.test(timeout_time=15, timeout_unit='us')
async def test(dut):
    tb = TB(dut)
    await tb.test()
