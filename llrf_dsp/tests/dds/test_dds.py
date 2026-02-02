import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from uspas_llrf.llrf_model.llrf_dsp import DDS, wrap_phase
import logging
import numpy as np


class TB:
    def __init__(self, dut, num: int = 4, den: int = 11):
        dut._log.setLevel(logging.INFO)
        self.dut = dut
        self.dwlo = dut.DWLO.value.to_unsigned()
        self.dwh = dut.DWH.value.to_unsigned()
        self.dwl = dut.DWL.value.to_unsigned()
        self.model = DDS(num=num, den=den, width=self.dwlo)
        cocotb.start_soon(Clock(dut.clk, 8, unit="ns").start())

    def log_banner(self, str):
        cocotb.log.warning('*'*20 + f"{str:^20s}" + '*'*20)

    async def cycle_reset(self):
        for val in [0, 1, 0]:
            self.dut.reset.value = val
            await RisingEdge(self.dut.clk)

    async def init_test(self) -> None:
        self.model.amp = int(
            random.uniform(0.8, 0.95) * self.model.full_scale_amp)
        self.model.phase_shift_deg = phs_shift = random.randint(-180, 180)
        phase_step_h, phase_step_l, modulo = self.model.calc_dds_config(
            dwh=self.dwh, dwl=self.dwl)
        self.dut.phase_step_h.value = phase_step_h
        # test asynchronous program of phase_step_h, phase_step_l
        await RisingEdge(self.dut.clk)
        self.dut.phase_step_l.value = phase_step_l
        self.dut.modulo.value = modulo
        self.dut.amplitude.value = self.model.amp
        await self.cycle_reset()
        self.dut.phase_shift.value = \
            self.model.encode_phase(phs_shift)
        amp_exp = np.abs(self.model.gain) * (1 << self.model.width - 1)
        phs_exp = np.angle(self.model.gain, deg=True)
        await self.cycle_reset()
        return amp_exp, phs_exp

    async def check_sig(self, amp_exp, phs_off) -> None:
        phs_step_exp = np.rad2deg(self.model.omega)
        cocotb.log.warning(
            f"expected mag: {amp_exp:8.2f} cnt,  phs: {phs_off:8.2f} deg,  "
            f"phs_step: {phs_step_exp:8.2f} deg")
        for ix in range(8):
            await RisingEdge(self.dut.clk)
            i_meas = self.dut.cos_out.value.to_signed()
            q_meas = self.dut.sin_out.value.to_signed()
            iq_meas = i_meas + 1j * q_meas
            amp_meas = np.abs(iq_meas)
            phs_meas = np.angle(iq_meas, deg=True)
            phs_exp = wrap_phase(phs_off + ix * phs_step_exp)
            cocotb.log.warning(
                f"measured mag: {amp_meas:8.2f} cnt,  "
                f"phs: {phs_meas:8.2f} deg,  ")
            amp_err = abs(amp_meas - amp_exp) / amp_exp
            phs_err = abs(wrap_phase(phs_meas - phs_exp))
            assert amp_err < 0.001, "amplitude out-of-bound of 0.1%"
            assert phs_err < 0.1, "phase out-of-bound of 0.1 deg"

    async def test(self):
        cocotb.log.info(f'LLRF Model:\n{self.model}')
        amp_exp, phs_off = await self.init_test()
        await ClockCycles(self.dut.clk, self.model.CORDIC_LATENCY)
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
