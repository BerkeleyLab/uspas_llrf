import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from llrf_model.llrf_dsp import DSPCoreTX, wrap_phase
import logging
import numpy as np
import itertools


class TB:
    def __init__(self, dut, num: int = 4, den: int = 11,
                 spectral_flip: bool = False):
        dut._log.setLevel(logging.INFO)
        self.dut = dut
        assert num > 0 and den > 0, "num and den must be positive integers"
        self.spectral_flip = spectral_flip
        # DSPCoreTX is in dac_clock domain
        # duc_pipeline is the number of clock cycles
        self.model = DSPCoreTX(num=num, den=den,
                               has_cordic=False, duc_pipeline=8)
        cocotb.start_soon(Clock(dut.dsp_clk, 8, units="ns").start())
        cocotb.start_soon(Clock(dut.dac_clk, 4, units="ns").start())

    def log_banner(self, str):
        self.dut._log.warning('*'*20 + f"{str:^20s}" + '*'*20)

    async def cycle_reset(self):
        self.dut.dsp_reset.setimmediatevalue(0)
        await ClockCycles(self.dut.dsp_clk, 2)
        for val in [1, 0]:
            self.dut.dsp_reset.value = val
            await RisingEdge(self.dut.dsp_clk)

    async def drive_dds(self) -> None:
        """ Drive the DDS in the DAC clock domain. """
        for t in itertools.count():
            nco = self.model.dds.amp * np.exp(1j * (self.model.omega * t))
            nco *= self.model.CORDIC_GAIN
            self.dut.cosa.value = int(nco.real)
            self.dut.sina.value = int(nco.imag)
            await RisingEdge(self.dut.dac_clk)

    async def drive_dac(self, amp=1, omega=0, phs=0) -> None:
        """ Drive the DAC input at base band in the DSP clock domain. """
        for t in itertools.count():
            sig = amp * np.exp(1j * (omega * t + np.deg2rad(phs)))
            self.dut.i_data_in.value = int(sig.real)
            self.dut.i_data_valid.value = 1
            self.dut.q_data_in.value = int(sig.imag)
            self.dut.q_data_valid.value = 1
            await RisingEdge(self.dut.dsp_clk)

    async def init_test(self) -> None:
        amp_exp = (1 << (self.dut.DWO.value - 1)) * 0.95
        phs_exp = random.randint(-180, 180)
        await self.cycle_reset()
        self.dut._log.debug('reset done.')
        self.dut.spectral_flip.value = self.spectral_flip
        cocotb.start_soon(self.drive_dds())
        cocotb.start_soon(self.drive_dac(amp=amp_exp, phs=phs_exp))
        amp_exp *= np.abs(self.model.gain)
        # base band signal is lag of DDS
        if self.spectral_flip:
            phs_exp = wrap_phase(phs_exp + np.angle(self.model.gain, deg=True))
        else:
            phs_exp = wrap_phase(phs_exp - np.angle(self.model.gain, deg=True))
        return amp_exp, phs_exp

    async def check_sig(self, amp_exp, phs_off) -> None:
        phs_step_exp = np.rad2deg(self.model.omega)
        if self.spectral_flip:
            phs_step_exp = -phs_step_exp
        self.dut._log.warning(
            f"expected mag: {amp_exp:8.2f} cnt,  phs: {phs_off:8.2f} deg,  "
            f"  omega: {phs_step_exp:8.2f} deg")
        for ix in range(8):
            i_meas = self.dut.dac_i_out.value.signed_integer
            q_meas = self.dut.dac_q_out.value.signed_integer
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
            await RisingEdge(self.dut.dac_clk)

    async def test(self):
        self.dut._log.info(f'LLRF Model:\n{self.model}')
        amp_exp, phs_exp = await self.init_test()
        await ClockCycles(self.dut.dac_clk, self.model.duc_pipeline + 4)
        await self.check_sig(amp_exp, phs_exp)


@cocotb.test(timeout_time=1, timeout_unit='us')
async def test_alsu(dut):
    tb = TB(dut, num=4, den=11*2)
    tb.log_banner('ALSU DDS Test')
    await tb.test()


@cocotb.test(timeout_time=1, timeout_unit='us')
async def test_uspas(dut):
    tb = TB(dut, num=4, den=23*2)
    tb.log_banner('USPAS DDS Test')
    await tb.test()


@cocotb.test(timeout_time=1, timeout_unit='us')
async def test_lemp(dut):
    tb = TB(dut, num=11, den=28)
    tb.log_banner('LEMP DDS Test')
    await tb.test()


@cocotb.test(timeout_time=1, timeout_unit='us')
async def test_awa(dut):
    # Second Nyquist zone
    # IF / DAC = 203 / 264
    tb = TB(dut, num=(264-203), den=264, spectral_flip=True)
    tb.log_banner('AWA DDS Test')
    await tb.test()
