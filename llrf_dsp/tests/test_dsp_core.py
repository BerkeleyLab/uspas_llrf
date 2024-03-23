import numpy as np
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from cocotb.handle import SimHandleBase
from llrf_model import LLRFModel
import random
import logging


class TestLLRF:
    def __init__(self, dut: SimHandleBase, f_config='USPAS') -> None:
        self.dut = dut
        self.llrf = LLRFModel(conf=f_config)
        dut._log.setLevel(logging.INFO)
        dut._log.info(f"Simulating: {f_config}")
        self.dut.rx_phase_offset.value = self.encode_phase(
            self.llrf.rx.phase_off_deg, width=19)
        self.dut.tx_phase_offset.value = self.encode_phase(
            self.llrf.tx.phase_off_deg, width=19)
        clock = Clock(self.dut.clk, self.llrf.DSP_CLK_CYCLE, units="ns")
        cocotb.start_soon(clock.start())

    def wrap_phase(self, phs: float, deg=True):
        """Wrap phase value to be within [-180, 180] or [-pi, pi].

        Args:
            phs (float): unwrapped phase value
            deg (bool, optional): unit is degree. Defaults to True.

        Returns:
            wrapped_phase (float): wrapped phase
        """
        scale = 180 if deg else np.pi
        return (phs + scale) % (2 * scale) - scale

    def encode_phase(self, phs: float, deg=True, width=19):
        """Convert phase value to register

        Args:
            phs (float): phase value in deg or radian units.
            deg (bool, optional): unit is degree. Defaults to True.
            width (int, optional): register data width. Defaults to 19.

        Returns:
            reg: encoded register value
        """
        scale = 360 if deg else (2 * np.pi)
        return int(phs / scale * 2**width)

    def decode_phase(self, signal: SimHandleBase, deg=True):
        """Convert phase value from register

        Args:
            signal (SimHandleBase): signal handle.
            deg (bool, optional): unit is degree. Defaults to True.
            width (int, optional): register data width. Defaults to 19.

        Returns:
            phs: phase value in deg or radian units.
        """
        scale = 360 if deg else (2 * np.pi)
        reg = signal.value.signed_integer
        width = len(signal)
        return self.wrap_phase(reg / 2**width * scale)

    async def test_rx(self, n_steps=100) -> None:
        self.dut._log.info('**********     RX testing     **********')
        self.dut._log.info(f'LLRFModel RX:\n{self.llrf.rx}')
        self.dut._log.info('*' * 40)

        await self.reset_dut()
        amp_exp = self.llrf.max_adc_amp
        phs_exp = self.wrap_phase(random.random() * 360)
        cocotb.start_soon(self.drive_dds(n_steps=n_steps))
        cocotb.start_soon(self.drive_adc(amp_exp, phs_exp, n_steps=n_steps))
        await ClockCycles(self.dut.clk, n_steps-5)  # settling time of filters
        await self.check_sig(amp_exp, phs_exp)

    async def test_open_loop(self, n_steps=400) -> None:
        self.dut._log.info('**********  OpenLoop testing  **********')
        self.dut._log.info(f'LLRFModel TX:\n{self.llrf.tx}')
        self.dut._log.info('*' * 40)

        await self.reset_dut()
        amp_exp = 10000
        phs_exp = self.wrap_phase(random.random() * 360)
        phs_exp = 0
        amp_setp, phs_setp = self.llrf.calc_open_loop_setp(amp_exp, phs_exp)
        self.dut.amp_setpoint.value = amp_setp
        self.dut.phs_setpoint.value = phs_setp

        cocotb.start_soon(self.drive_dds(n_steps=n_steps))
        cocotb.start_soon(self.loopback(n_steps=n_steps))
        await ClockCycles(self.dut.clk, n_steps-5)  # settling time of filters
        await self.check_sig(amp_exp, phs_exp)

    async def reset_dut(self) -> None:
        await RisingEdge(self.dut.clk)
        self.dut.reset.value = 1
        await RisingEdge(self.dut.clk)
        self.dut.reset.value = 0

    async def drive_dds(self, n_steps=256) -> None:
        for nco in self.llrf.gen_sinusoidal(
                amp=self.llrf.LO_AMP, n_samples=n_steps):
            await RisingEdge(self.dut.clk)
            nco *= self.llrf.CORDIC_GAIN
            self.dut.cosa.value = int(nco.real)
            self.dut.sina.value = int(nco.imag)

    async def drive_adc(self, amp, phs, n_steps=256) -> None:
        for sig in self.llrf.gen_sinusoidal(
                amp, phs, n_samples=n_steps):
            await RisingEdge(self.dut.clk)
            self.dut.cav_field.value = int(sig.real)

    async def loopback(self, n_steps=256) -> None:
        for _ in range(n_steps):
            await RisingEdge(self.dut.clk)
            self.dut.cav_field.value = self.dut.dac_out.value.signed_integer

    async def check_sig(self, amp_exp, phs_exp) -> None:
        self.dut._log.info(
            f"expected mag: {amp_exp:8.2f} cnt, phs: {phs_exp:6.3f} deg")
        for _ in range(5):
            await RisingEdge(self.dut.clk)
            i_meas = self.dut.field_i.value.signed_integer
            q_meas = self.dut.field_q.value.signed_integer
            iq_meas = i_meas + 1j * q_meas
            amp_meas = self.dut.amp_measured.value.signed_integer
            amp_meas /= np.abs(self.llrf.rx.gain)
            phs_meas = self.decode_phase(self.dut.phs_measured)
            self.dut._log.debug(
                f"raw IQ   mag: {np.abs(iq_meas):8.2f} cnt, "
                f"phs: {np.angle(iq_meas, deg=True):6.3f} deg")
            self.dut._log.info(
                f"measured mag: {amp_meas:8.2f} cnt, "
                f"phs: {phs_meas:6.3f} deg")
            assert -0.1 < (amp_meas - amp_exp) / amp_exp < 0.01, \
                "RX amplitude out-of-bound of 0.1%"
            assert -0.1 < self.wrap_phase(phs_meas - phs_exp) < 0.1, \
                "RX phase out-of-bound of 0.1 deg"


@cocotb.test()
async def test_alsu(dut):
    tester = TestLLRF(dut, f_config='ALSU')
    await tester.test_rx()
    await tester.test_open_loop()


@cocotb.test()
async def test_uspas(dut):
    tester = TestLLRF(dut, f_config='USPAS')
    await tester.test_rx()
    await tester.test_open_loop()


@cocotb.test()
async def test_lemp(dut):
    tester = TestLLRF(dut, f_config='LEMP')
    await tester.test_rx()
    await tester.test_open_loop()
