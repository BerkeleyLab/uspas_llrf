import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from llrf_dsp import LLRFModule, DDS, DDC, WashoutFilter
import logging
import numpy as np
import itertools


class DDCTest(LLRFModule):
    LO_AMP = 74840
    def __init__(self, num: int = 4, den: int = 11,
                 dds: DDS = None) -> None:
        """Numerical model for ddc.v.

        Args:
            num (int): numerator of IF / Fs. Defaults to 4.
            den (int): denominator of IF / Fs. Defaults to 11.
            dds (DDS): external dds.
        """
        super().__init__(num, den)
        if dds is None:
            dds = DDS(amp=self.LO_AMP, num=num, den=den)

        self.submodules += [
            WashoutFilter(num=num, den=den),
            dds,
            DDC(num=num, den=den)]


class TB:
    def __init__(self, dut):
        dut._log.setLevel(logging.WARNING)
        self.dut = dut
        self.llrf = DDCTest()
        cocotb.start_soon(Clock(dut.clk, 8, units="ns").start())

    def log_banner(self, str):
        self.dut._log.warning('*'*20 + f"{str:^20s}" + '*'*20)

    def wrap_phase(self, phs: float, deg=True):
        """Wrap phase value to be within [-180, 180] or [-pi, pi].
        """
        scale = 180 if deg else np.pi
        return (phs + scale) % (2 * scale) - scale

    def clamp(self, value, min_value, max_value):
        return max(min_value, min(value, max_value))

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
            nco = self.llrf.LO_AMP * np.exp(1j * (self.llrf.omega * t))
            nco *= self.llrf.CORDIC_GAIN
            await RisingEdge(self.dut.clk)
            self.dut.cosa.value = int(nco.real)
            self.dut.sina.value = int(nco.imag)

    async def drive_adc(self, amp, phs, noise_amp=3) -> None:
        for t in itertools.count():
            sig = amp * np.exp(1j * (self.llrf.omega * t + np.deg2rad(phs)))
            noise = random.randint(-noise_amp, noise_amp)
            await RisingEdge(self.dut.clk)
            self.dut.adc.value = self.clamp(
                int(sig.real + noise), -32768, 32767)

    async def init_test(self) -> None:
        await self.cycle_reset()
        amp_exp = (1 << 15) / np.abs(self.llrf.gain) * 0.95
        phs_exp = random.randint(-180, 180)
        cocotb.start_soon(self.drive_dds())
        cocotb.start_soon(self.drive_i_sel())
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
            amp_meas /= np.abs(self.llrf.gain)
            phs_meas = np.angle(iq_meas, deg=True)
            phs_meas = self.wrap_phase(
                phs_meas - np.angle(self.llrf.gain, deg=True))
            self.dut._log.debug(
                f"raw IQ   mag: {np.abs(iq_meas):8.2f} cnt,  "
                f"phs: {np.angle(iq_meas, deg=True):8.2f} deg")
            self.dut._log.warning(
                f"measured mag: {amp_meas:8.2f} cnt,  "
                f"phs: {phs_meas:8.2f} deg")
            assert abs(amp_meas - amp_exp) / amp_exp < 0.1, \
                "RX amplitude out-of-bound of 0.1%"
            assert abs(self.wrap_phase(phs_meas - phs_exp)) < 0.1, \
                "RX phase out-of-bound of 0.1 deg"

    async def test_rx(self, wait=200):
        self.log_banner('RX Test')
        amp_exp, phs_exp = await self.init_test()
        cocotb.start_soon(self.drive_adc(amp_exp, phs_exp))
        await ClockCycles(self.dut.clk, wait)  # settling time of filters
        await self.check_sig(amp_exp, phs_exp)


@cocotb.test(timeout_time=15, timeout_unit='us')
async def test_rx(dut):
    tb = TB(dut)
    for _ in range(3):
        await tb.test_rx()
