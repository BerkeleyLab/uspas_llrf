import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from llrf_dsp import DSPCoreTX, wrap_phase
import logging
import numpy as np
import itertools


class TB:
    def __init__(self, dut, num: int = 4, den: int = 11):
        dut._log.setLevel(logging.INFO)
        self.dut = dut
        self.model = DSPCoreTX(num=num, den=den, has_cordic=False)
        cocotb.start_soon(Clock(dut.dsp_clk, 8, units="ns").start())
        cocotb.start_soon(Clock(dut.dac_clk, 4, units="ns").start())

    def log_banner(self, str):
        self.dut._log.warning('*'*20 + f"{str:^20s}" + '*'*20)

    async def drive_dds(self) -> None:
        for t in itertools.count():
            nco = self.model.dds.amp * np.exp(1j * (self.model.omega * t))
            nco *= self.model.CORDIC_GAIN
            await RisingEdge(self.dut.dsp_clk)
            self.dut.cosa.value = int(nco.real)
            self.dut.sina.value = int(nco.imag)

    async def drive_dac(self, amp=1, omega=0, phs=0) -> None:
        for t in itertools.count():
            sig = amp * np.exp(1j * (omega * t + np.deg2rad(phs)))
            await RisingEdge(self.dut.dsp_clk)
            self.dut.i_data_in.value = int(sig.real)
            self.dut.q_data_in.value = int(sig.imag)

    async def init_test(self) -> None:
        amp_exp = (1 << (self.dut.DW.value - 1)) * 0.95
        phs_exp = random.randint(-180, 180)
        cocotb.start_soon(self.drive_dds())
        cocotb.start_soon(self.drive_dac(amp=amp_exp, omega=0, phs=phs_exp))
        amp_exp *= np.abs(self.model.gain)
        # complex output: no phase offset correction is needed
        return amp_exp, phs_exp

    async def check_sig(self, amp_exp, phs_off) -> None:
        phs_step_exp = np.rad2deg(self.model.omega)
        self.dut._log.warning(
            f"expected mag: {amp_exp:8.2f} cnt,  phs: {phs_off:8.2f} deg,  "
            f"  omega: {phs_step_exp:8.2f} deg")
        for ix in range(8):
            await RisingEdge(self.dut.dsp_clk)
            i_meas = self.dut.dac_in_data_i.value.signed_integer
            q_meas = self.dut.dac_in_data_q.value.signed_integer
            # await RisingEdge(self.dut.dac_clk)
            # i_meas = self.dut.dac_i_out.value.signed_integer
            # q_meas = self.dut.dac_q_out.value.signed_integer
            iq_meas = i_meas + 1j * q_meas
            amp_meas = np.abs(iq_meas)
            phs_meas = np.angle(iq_meas, deg=True)
            phs_exp = wrap_phase(phs_off + ix * phs_step_exp)
            self.dut._log.warning(
                f"measured mag: {amp_meas:8.2f} cnt,  "
                f"phs: {phs_meas:8.2f} deg,  "
                f"phs_exp: {phs_exp:8.2f} deg")
            amp_err = abs(amp_meas - amp_exp) / amp_exp
            phs_err = abs(wrap_phase(phs_meas - phs_exp))
            assert amp_err < 0.001, "amplitude out-of-bound of 0.1%"
            assert phs_err < 0.1, "phase out-of-bound of 0.1 deg"

    async def test(self, wait=4):
        self.dut._log.info(f'LLRF Model:\n{self.model}')
        amp_exp, phs_exp = await self.init_test()
        await ClockCycles(self.dut.dsp_clk, wait)
        await self.check_sig(amp_exp, phs_exp)


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
