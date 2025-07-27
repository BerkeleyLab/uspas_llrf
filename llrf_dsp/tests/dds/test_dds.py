import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from llrf_model.llrf_dsp import DDS, wrap_phase
import logging
import numpy as np


class TB:
    def __init__(self, dut, num: int = 4, den: int = 11):
        dut._log.setLevel(logging.INFO)
        self.dut = dut
        self.model = DDS(num=num, den=den,
                         amp=dut.LO_AMP.value, width=dut.DWLO.value)
        cocotb.start_soon(Clock(dut.clk, 8, units="ns").start())

    def log_banner(self, str):
        self.dut._log.warning('*'*20 + f"{str:^20s}" + '*'*20)

    async def cycle_reset(self):
        self.dut.reset.setimmediatevalue(0)
        await ClockCycles(self.dut.clk, 2)
        for val in [1, 0]:
            self.dut.reset.value = val
            await RisingEdge(self.dut.clk)

    async def init_test(self) -> None:
        phase_step_h, phase_step_l, modulo = self.model.calc_dds_config(
            dwh=self.dut.DWH.value, dwl=self.dut.DWL.value)
        self.dut.phase_step_h.value = phase_step_h
        # test asynchronous program of phase_step_h, phase_step_l
        await RisingEdge(self.dut.clk)
        self.dut.phase_step_l.value = phase_step_l
        self.dut.modulo.value = modulo
        await self.cycle_reset()
        phs_off = random.randint(-180, 180)
        self.dut.phase_shift.value = \
            int(phs_off / 360 * 2**(self.dut.DWLO.value + 1))
        amp_exp = int(self.model.amp) * self.model.CORDIC_GAIN
        return amp_exp, phs_off

    async def check_sig(self, amp_exp, phs_off) -> None:
        phs_step_exp = np.rad2deg(self.model.omega)
        self.dut._log.warning(
            f"expected mag: {amp_exp:8.2f} cnt,  phs: {phs_off:8.2f} deg,  "
            f"phs_step: {phs_step_exp:8.2f} deg")
        for ix in range(8):
            await RisingEdge(self.dut.clk)
            i_meas = self.dut.cos_out.value.signed_integer
            q_meas = self.dut.sin_out.value.signed_integer
            iq_meas = i_meas + 1j * q_meas
            amp_meas = np.abs(iq_meas)
            phs_meas = np.angle(iq_meas, deg=True)
            phs_exp = wrap_phase(phs_off + ix * phs_step_exp)
            self.dut._log.warning(
                f"measured mag: {amp_meas:8.2f} cnt,  "
                f"phs: {phs_meas:8.2f} deg,  ")
            amp_err = abs(amp_meas - amp_exp) / amp_exp
            phs_err = abs(wrap_phase(phs_meas - phs_exp))
            assert amp_err < 0.001, "amplitude out-of-bound of 0.1%"
            assert phs_err < 0.1, "phase out-of-bound of 0.1 deg"

    async def test(self, wait=22):
        self.dut._log.info(f'LLRF Model:\n{self.model}')
        amp_exp, phs_off = await self.init_test()
        await ClockCycles(self.dut.clk, wait)  # settling time of CORDIC
        await self.check_sig(amp_exp, phs_off)


@cocotb.test(timeout_time=1, timeout_unit='us')
async def test_alsu(dut):
    tb = TB(dut, num=4, den=11)
    tb.log_banner('ALSU DDS Test')
    await tb.test()


@cocotb.test(timeout_time=1, timeout_unit='us')
async def test_uspas(dut):
    tb = TB(dut, num=4, den=23)
    tb.log_banner('USPAS DDS Test')
    await tb.test()


@cocotb.test(timeout_time=1, timeout_unit='us')
async def test_lemp(dut):
    tb = TB(dut, num=3, den=14)
    tb.log_banner('LEMP DDS Test')
    await tb.test()


@cocotb.test(timeout_time=1, timeout_unit='us')
async def test_awa(dut):
    tb = TB(dut, num=7, den=33)
    tb.log_banner('AWA DDS Test')
    await tb.test()
