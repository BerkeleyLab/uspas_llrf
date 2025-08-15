import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from llrf_model.llrf_dsp import DSPCoreRX, wrap_phase, clip_int
import logging
import numpy as np
import itertools


class TB:
    def __init__(self, dut, num: int = 4, den: int = 11):
        dut._log.setLevel(logging.INFO)
        self.dut = dut
        self.model = DSPCoreRX(num, den, has_cordic=False)
        cocotb.start_soon(Clock(dut.clk, 8, units="ns").start())

    def log_banner(self, str):
        self.dut._log.info('*'*20 + f"{str:^20s}" + '*'*20)

    async def cycle_reset(self):
        self.dut.reset.setimmediatevalue(0)
        await ClockCycles(self.dut.clk, 2)
        for val in [1, 0]:
            self.dut.reset.value = val
            await RisingEdge(self.dut.clk)

    async def drive_i_sel(self) -> None:
        self.dut.i_sel.value = 0
        while True:
            await RisingEdge(self.dut.clk)
            self.dut.i_sel.value = not self.dut.i_sel.value

    async def drive_dds(self) -> None:
        for t in itertools.count():
            nco = self.model.dds.amp * np.exp(1j * (self.model.omega * t))
            nco *= self.model.CORDIC_GAIN
            await RisingEdge(self.dut.clk)
            self.dut.cosa.value = int(nco.real)
            self.dut.sina.value = int(nco.imag)

    async def drive_adc(self, amp, phs, noise_amp=3) -> None:
        for t in itertools.count():
            sig = amp * np.exp(1j * (self.model.omega * t + np.deg2rad(phs)))
            noise = random.randint(-noise_amp, noise_amp)
            await RisingEdge(self.dut.clk)
            self.dut.adc.value = clip_int(sig.real + noise)

    async def init_test(self, noise_amp=3) -> None:
        await self.cycle_reset()
        amp_exp = (1 << (self.dut.DWI.value - 1)) * 0.95
        amp_exp /= np.abs(self.model.gain)
        phs_exp = random.randint(-180, 180)
        cocotb.start_soon(self.drive_dds())
        cocotb.start_soon(self.drive_i_sel())
        cocotb.start_soon(self.drive_adc(amp_exp, phs_exp, noise_amp))
        phs_exp = wrap_phase(phs_exp + np.angle(self.model.gain, deg=True))
        return amp_exp, phs_exp

    async def check_sig(self, amp_exp, phs_exp) -> None:
        self.dut._log.warning(
            f"expected mag: {amp_exp:8.2f} cnt,  phs: {phs_exp:8.2f} deg")
        for _ in range(5):
            await RisingEdge(self.dut.clk)
            i_meas = self.dut.i_out.value.signed_integer
            q_meas = self.dut.q_out.value.signed_integer
            iq_meas = i_meas + 1j * q_meas
            amp_meas = np.abs(iq_meas)
            amp_meas /= np.abs(self.model.gain)
            phs_meas = np.angle(iq_meas, deg=True)
            self.dut._log.debug(
                f"raw IQ   mag: {np.abs(iq_meas):8.2f} cnt,  "
                f"phs: {np.angle(iq_meas, deg=True):8.2f} deg")
            self.dut._log.warning(
                f"measured mag: {amp_meas:8.2f} cnt,  "
                f"phs: {phs_meas:8.2f} deg")
            amp_err = abs(amp_meas - amp_exp) / amp_exp
            phs_err = abs(wrap_phase(phs_meas - phs_exp))
            assert amp_err < 0.001, "amplitude out-of-bound of 0.1%"
            assert phs_err < 0.1, "phase out-of-bound of 0.1 deg"

    async def test(self, wait=200):
        self.dut._log.info(f'LLRF Model:\n{self.model}')
        amp_exp, phs_exp = await self.init_test()
        await ClockCycles(self.dut.clk, wait)  # settling time of filters
        await self.check_sig(amp_exp, phs_exp)


@cocotb.test(timeout_time=15, timeout_unit='us')
async def test_alsu(dut):
    tb = TB(dut, num=4, den=11)
    tb.log_banner('ALSU')
    await tb.test()


@cocotb.test(timeout_time=15, timeout_unit='us')
async def test_uspas(dut):
    tb = TB(dut, num=4, den=23)
    tb.log_banner('USPAS')
    await tb.test()


@cocotb.test(timeout_time=15, timeout_unit='us')
async def test_lemp(dut):
    tb = TB(dut, num=3, den=14)
    tb.log_banner('LEMP')
    await tb.test()


@cocotb.test(timeout_time=15, timeout_unit='us')
async def test_awa(dut):
    tb = TB(dut, num=7, den=33)
    tb.log_banner('AWA')
    await tb.test()
