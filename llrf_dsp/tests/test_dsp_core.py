import numpy as np
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from llrf_model import LLRFModel


@cocotb.test()
async def test_noniq_ddc(dut):
    model = LLRFModel(conf='LEMP')
    clock = Clock(dut.clk, model.DSP_CLK_CYCLE, units="ns")
    cocotb.start_soon(clock.start())

    await RisingEdge(dut.clk)
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0

    amp_exp = 10000
    phs_exp = np.pi / 6
    for lo, sig in zip(
            model.gen_signal(),
            model.gen_signal(amp_exp, phs_exp)):
        await RisingEdge(dut.clk)
        dut.cosa.value = int(lo.real)
        dut.sina.value = int(lo.imag)
        dut.cav_field.value = int(sig.real)
        sig_meas = int(dut.field_i) + 1j * int(dut.field_q)
        dut._log.debug(
            "sig mag: %.1f cnt, phs: %.1f deg",
            np.abs(sig_meas), np.angle(sig_meas, deg=True))
