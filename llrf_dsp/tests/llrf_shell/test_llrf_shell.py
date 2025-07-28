import cocotb
from cocotb.clock import Clock
from llrf_model.llrf_dsp import LLRFModel
from local_bus import LocalbusAppMaster
import logging


class TB:
    def __init__(self, dut, f_config='USPAS', settings_fname='settings.json'):
        dut._log.setLevel(logging.INFO)
        self.dut = dut
        self.llrf = llrf = LLRFModel(f_config, settings_fname)
        self.lb = LocalbusAppMaster(
            dut, dut.lb_clk, regmap_json_path='../../llrf_shell.json')
        cocotb.start_soon(Clock(dut.lb_clk, 8, units="ns").start())
        cocotb.start_soon(
            Clock(dut.dsp_clk, llrf.DSP_CLK_CYCLE, units="ns").start())

    def log_banner(self, str):
        self.dut._log.warning('*'*20 + f"{str:^20s}" + '*'*20)

    async def init_test(self):
        await self.lb.write_reg('dds_phase_step', 0xdeadbeaf)

    async def test(self, wait=200):
        await self.init_test()
        val = await self.lb.read_reg('dds_phase_step')
        assert val == 0xdeadbeaf, \
            f"Expected 0xdeadbeaf, got {val}"
        self.dut._log.info(f"Read dds_phase_step: {val}")


@cocotb.test(timeout_time=15, timeout_unit='us')
async def test(dut):
    tb = TB(dut)
    await tb.test()
