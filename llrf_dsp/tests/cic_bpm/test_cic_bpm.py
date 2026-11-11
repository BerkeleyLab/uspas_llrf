import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotb.handle import Immediate
from uspas_llrf import BPM, clip_int
import logging
import numpy as np
import itertools


class TB_cic_bpm:
    def __init__(self, dut, num: int = 4, den: int = 11):
        dut._log.setLevel(logging.INFO)
        self.dut = dut
        self.dw = self.dut.DW.value.to_unsigned()
        self.dwlo = self.dut.DWLO.value.to_unsigned()
        self.dwh = self.dut.DWH.value.to_unsigned()
        self.dwl = self.dut.DWL.value.to_unsigned()
        self.ex0 = self.dut.EX0.value.to_unsigned()
        self.ex1 = self.dut.EX1.value.to_unsigned()
        self.ex2 = self.dut.EX2.value.to_unsigned()
        self.model = BPM(
            num=num, den=den, ex0=self.ex0, ex1=self.ex1, ex2=self.ex2)

        # Initialize input values
        for ch in range(4):
            self.dut.adc_array_in[ch].value = 0
        self.dut.i_sel.set(Immediate(0))
        self.dut.sig_valid.value = 1
        self.dut.gpioData.value = 0
        self.dut.csrStrobe.value = 0
        self.dut.xCalStrobe.value = 0
        self.dut.yCalStrobe.value = 0
        self.dut.qCalStrobe.value = 0

        cocotb.start_soon(Clock(dut.clk, 8, unit="ns").start())

    def log_banner(self, str):
        cocotb.log.info('*' * 20 + f"{str:^20s}" + '*' * 20)

    async def cycle_reset(self):
        for val in [0, 1, 0]:
            self.dut.reset.value = val
            await RisingEdge(self.dut.clk)

    async def drive_i_sel(self) -> None:
        while True:
            await RisingEdge(self.dut.clk)
            self.dut.i_sel.value = not self.dut.i_sel.value

    async def drive_dds(self) -> None:
        """Initialize DDS configuration and drive phase/frequency registers."""
        phase_step_h, phase_step_l, modulo = self.model.dds.calc_dds_config(
            dwh=self.dwh, dwl=self.dwl)
        self.dut.phase_step_h.value = phase_step_h
        self.dut.phase_step_l.value = phase_step_l
        self.dut.modulo.value = modulo
        self.dut.amplitude.value = self.model.dds.amp
        self.dut.phase_shift.value = 0

    async def drive_adc(self, amp_list, phs_list, dc=10, noise_amp=3) -> None:
        """Drive 4-channel button ADC raw inputs with known IF signals."""
        for t in itertools.count():
            await RisingEdge(self.dut.clk)
            for ch in range(4):
                amp = amp_list[ch]
                phs = phs_list[ch]
                sig = amp * np.exp(
                    1j * (self.model.omega * t + np.deg2rad(phs)))
                noise = random.randint(-noise_amp, noise_amp)
                self.dut.adc_array_in[ch].value = clip_int(
                    sig.real + dc + noise, n_bit=self.dw)

    async def init_test(self, amp_list=None, phs_list=None, noise_amp=3):
        if amp_list is None:
            amp_nominal = (1 << (self.dw - 1)) * 0.75
            amp_list = [amp_nominal] * 4
        if phs_list is None:
            phs_list = [0.0, 0.0, 0.0, 0.0]

        await self.drive_dds()
        cocotb.start_soon(self.drive_i_sel())
        cocotb.start_soon(
            self.drive_adc(amp_list, phs_list, noise_amp=noise_amp))
        await self.cycle_reset()
        return amp_list, phs_list

    async def check_sig(self, amp_list, wait_cycles=4500):
        """Validate signal gain through DDC, CORDIC,
        and 3 series CIC stages.
        """
        # Scale factor accounts for DWBB -> DW bit truncation
        scale_bb = 1.0 / (1 << (self.dut.DWBB.value.to_unsigned() - self.dw))
        amp_exp_buttons = [
            a * np.abs(self.model.gain) * scale_bb for a in amp_list
        ]
        sum_exp = sum(amp_exp_buttons)

        cocotb.log.info(
            f"Expected Button Mag: {amp_exp_buttons[0]:.2f}, "
            f"Expected Sum (S): {sum_exp:.2f}")

        # Monitor TbT, FA, SA outputs over wait_cycles
        tbt_s_vals = []
        fa_s_vals = []
        sa_s_vals = []

        for _ in range(wait_cycles):
            await RisingEdge(self.dut.clk)
            if self.dut.tbtValid.value:
                tbt_s_vals.append(self.dut.tbtS.value.to_unsigned())
            if self.dut.faValid.value:
                fa_s_vals.append(self.dut.faS.value.to_unsigned())
            if self.dut.saValid.value:
                sa_s_vals.append(self.dut.saS.value.to_unsigned())

        assert len(tbt_s_vals) > 0, "No TbT valid samples received"
        assert len(fa_s_vals) > 0, "No FA valid samples received"
        assert len(sa_s_vals) > 0, "No SA valid samples received"

        # Check last settled samples for all 3 decimation stages
        meas_tbt = tbt_s_vals[-1]
        meas_fa = fa_s_vals[-1]
        meas_sa = sa_s_vals[-1]

        err_tbt = abs(meas_tbt - sum_exp) / sum_exp
        err_fa = abs(meas_fa - sum_exp) / sum_exp
        err_sa = abs(meas_sa - sum_exp) / sum_exp

        cocotb.log.warning(
            f"TbT S meas: {meas_tbt:8.2f}, err: {err_tbt * 100:.2f}%\n"
            f"FA  S meas: {meas_fa:8.2f}, err: {err_fa * 100:.2f}%\n"
            f"SA  S meas: {meas_sa:8.2f}, err: {err_sa * 100:.2f}%")

        assert err_tbt < 0.05, f"TbT Sum error {err_tbt * 100:.2f}% exceeds 5%"
        assert err_fa < 0.05, f"FA Sum error {err_fa * 100:.2f}% exceeds 5%"
        assert err_sa < 0.05, f"SA Sum error {err_sa * 100:.2f}% exceeds 5%"

    async def test(self, wait=4500):
        self.log_banner(f'Testing {self.model.num}/{self.model.den}')
        cocotb.log.info(f'BPM Model:\n{self.model}')
        amp_list, _ = await self.init_test()
        await self.check_sig(amp_list, wait_cycles=wait)
        cocotb.log.info("Completed simulation test run.")


@cocotb.test(timeout_time=60, timeout_unit='us')
async def test_alsu(dut):
    tb = TB_cic_bpm(dut, num=4, den=11)
    tb.log_banner('ALSU BPM Test')
    await tb.test()


@cocotb.test(timeout_time=60, timeout_unit='us')
async def test_uspas(dut):
    tb = TB_cic_bpm(dut, num=4, den=23)
    tb.log_banner('USPAS BPM Test')
    await tb.test()


@cocotb.test(timeout_time=60, timeout_unit='us')
async def test_lemp(dut):
    tb = TB_cic_bpm(dut, num=3, den=14)
    tb.log_banner('LEMP BPM Test')
    await tb.test()


@cocotb.test(timeout_time=60, timeout_unit='us')
async def test_awa(dut):
    tb = TB_cic_bpm(dut, num=7, den=33)
    tb.log_banner('AWA BPM Test')
    await tb.test()
