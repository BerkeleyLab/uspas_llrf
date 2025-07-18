import numpy as np
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer
from cocotb.handle import SimHandleBase
from llrf_model import LLRFModel
from plant import Plant
import itertools
import random
import logging


class TestLLRF:
    def __init__(self, dut: SimHandleBase,
                 f_config='USPAS', settings_fname='settings.json'):
        dut._log.setLevel(logging.INFO)
        self.dut = dut
        self.llrf = llrf = LLRFModel(f_config, settings_fname)
        self.plant = Plant(
            conf=f_config, settings_fname='cavity.json', llrf=llrf)
        self.log_banner(f'Simulating: {f_config}')
        rx_phase_off_reg = self.encode_phase(-llrf.rx.phase_off_deg)
        tx_phase_off_reg = self.encode_phase(-llrf.tx.phase_off_deg)
        self.dut.rx_phase_offset.value = rx_phase_off_reg
        self.dut.tx_phase_offset.value = tx_phase_off_reg
        self.dut._log.info(
            f'RX phase off: {llrf.rx.phase_off_deg:8.2f} deg; '
            f'TX phase off: {llrf.tx.phase_off_deg:8.2f} deg')
        self.dut._log.info(
            f'RX phase off: {rx_phase_off_reg:8d} cnt; '
            f'TX phase off: {tx_phase_off_reg:8d} cnt')
        self.dut._log.info(f'inlk_gain: {llrf.inlk_gain:10.6f}')
        self.dut._log.info(f'mon_gain:  {llrf.mon_gain:10.6f}')
        # validate settings.json against calculated values
        assert np.abs(llrf.rx.phase_off_deg - llrf.RX_LO_PHS_DEG) < 1e-4, \
            "Unexpected RX_LO_PHS_DEG."
        assert np.abs(llrf.tx.phase_off_deg - llrf.TX_LO_PHS_DEG) < 1e-4, \
            "Unexpected TX_LO_PHS_DEG."
        assert np.abs(llrf.inlk_gain - llrf.INLK_GAIN) / llrf.inlk_gain \
            < 1e-4, "Unexpected INLK_GAIN."
        assert np.abs(llrf.mon_gain - llrf.MON_GAIN) / llrf.inlk_gain \
            < 1e-4, "Unexpected MON_GAIN."
        clock = Clock(self.dut.clk, llrf.DSP_CLK_CYCLE, units="ns")
        cocotb.start_soon(clock.start())

    def log_banner(self, str):
        self.dut._log.info('*'*20 + f"{str:^20s}" + '*'*20)

    def wrap_phase(self, phs: float, deg=True):
        """Wrap phase value to be within [-180, 180] or [-pi, pi].
        """
        scale = 180 if deg else np.pi
        return (phs + scale) % (2 * scale) - scale

    def encode_phase(self, phs: float, deg=True, width=19):
        """Convert phase value to register
        """
        scale = 360 if deg else (2 * np.pi)
        return int(phs / scale * 2**width)

    def decode_phase(self, signal: SimHandleBase, deg=True):
        """Convert phase value from register
        """
        scale = 360 if deg else (2 * np.pi)
        reg = signal.value.signed_integer
        width = len(signal)
        return self.wrap_phase(reg / 2**width * scale)

    async def init_test(self) -> None:
        await self.reset_dut()
        # scramble internal init states of dut:
        await ClockCycles(self.dut.clk, random.randint(0, 20))
        amp_exp = self.llrf.max_adc_amp
        phs_exp = self.wrap_phase(random.random() * 360)
        cocotb.start_soon(self.drive_dds())
        return amp_exp, phs_exp

    async def test_rx(self, wait=200) -> None:
        self.log_banner('RX Test')
        self.dut._log.info(f'LLRFModel RX:\n{self.llrf.rx}')
        # validate settings.json against calculated values
        assert -0.0001 < self.llrf.AMP_RX_GAIN - np.abs(self.llrf.rx.gain) \
            < 0.0001, "Unexpected AMP_RX_GAIN."

        amp_exp, phs_exp = await self.init_test()
        cocotb.start_soon(self.drive_adc(amp_exp, phs_exp))
        await ClockCycles(self.dut.clk, wait)  # settling time of filters
        await self.check_sig(amp_exp, phs_exp)

    async def test_open_loop(self, wait=320) -> None:
        self.log_banner('Open Loop Test')
        self.dut._log.info(f'LLRFModel TX:\n{self.llrf.tx}')

        amp_exp, phs_exp = await self.init_test()
        amp_setp, phs_setp = self.llrf.calc_open_loop_setp(amp_exp, phs_exp)
        self.dut.amp_setpoint.value = amp_setp
        self.dut.phs_setpoint.value = phs_setp
        cocotb.start_soon(self.loopback())
        await ClockCycles(self.dut.clk, wait)  # settling time
        await self.check_sig(amp_exp, phs_exp)

    async def test_close_loop(self, wait=2020) -> None:
        self.log_banner('Close Loop Test')
        self.dut._log.info(f'Cavity Model:\n{self.plant.cav}')

        amp_exp, phs_exp = await self.init_test()
        amp_exp *= 0.90  # to allow loop headroom
        amp_setp, phs_setp = self.llrf.calc_close_loop_setp(amp_exp, phs_exp)
        self.dut.amp_setpoint.value = amp_setp
        self.dut.phs_setpoint.value = phs_setp
        await self.init_loops(amp_setp, phs_setp)
        cocotb.start_soon(self.feedback())
        await ClockCycles(self.dut.clk, wait)  # settling time of loops
        await self.check_sig(amp_exp, phs_exp)

    async def reset_dut(self) -> None:
        await RisingEdge(self.dut.clk)
        self.dut.amp_loop_enable.value = 0
        self.dut.phs_loop_enable.value = 0
        self.dut.reset.value = 1
        await RisingEdge(self.dut.clk)
        self.dut.reset.value = 0

    async def init_loops(self, amp_setp, phs_setp) -> None:
        await RisingEdge(self.dut.clk)
        self.dut.amp_loop_reset.value = 1
        self.dut.phs_loop_reset.value = 1
        self.dut.Kp_amp.value = 80
        self.dut.Kp_phs.value = 80
        self.dut.Ki_amp.value = 200
        self.dut.Ki_phs.value = 500
        await RisingEdge(self.dut.clk)
        self.dut.amp_loop_enable.value = 1
        self.dut.phs_loop_enable.value = 1
        await RisingEdge(self.dut.clk)
        self.dut.amp_loop_reset.value = 0
        self.dut.phs_loop_reset.value = 0

    async def drive_dds(self) -> None:
        for t in itertools.count():
            nco = self.llrf.LO_AMP * np.exp(1j * (self.llrf.omega * t))
            nco *= self.llrf.CORDIC_GAIN
            await RisingEdge(self.dut.clk)
            self.dut.cosa.value = int(nco.real)
            self.dut.sina.value = int(nco.imag)

    async def drive_adc(self, amp, phs) -> None:
        for t in itertools.count():
            sig = amp * np.exp(1j * (self.llrf.omega * t + np.deg2rad(phs)))
            await RisingEdge(self.dut.clk)
            self.dut.adc_in.value = int(sig.real)

    async def loopback(self) -> None:
        while True:
            await RisingEdge(self.dut.clk)
            self.dut.adc_in.setimmediatevalue(
                self.dut.dac_out.value.signed_integer)

    async def feedback(self) -> None:
        while True:
            await self.plant.i_queue.put(self.dut.dac_out.value.signed_integer)
            await Timer(2, 'ns')  # delay by cable
            y = int(await self.plant.o_queue.get())
            self.dut.adc_in.value = min(max(y, -32678), 32767)

    async def check_sig(self, amp_exp, phs_exp) -> None:
        self.dut._log.info(
            f"expected mag: {amp_exp:8.2f} cnt,  phs: {phs_exp:6.3f} deg")
        for _ in range(5):
            await RisingEdge(self.dut.clk)
            i_meas = self.dut.field_i.value.signed_integer
            q_meas = self.dut.field_q.value.signed_integer
            iq_meas = i_meas + 1j * q_meas
            amp_meas = self.dut.amp_measured.value.signed_integer
            amp_meas /= np.abs(self.llrf.rx.gain)
            phs_meas = self.decode_phase(self.dut.phs_measured)
            self.dut._log.debug(
                f"raw IQ   mag: {np.abs(iq_meas):8.2f} cnt,  "
                f"phs: {np.angle(iq_meas, deg=True):6.3f} deg")
            self.dut._log.info(
                f"measured mag: {amp_meas:8.2f} cnt,  "
                f"phs: {phs_meas:6.3f} deg")
            assert -0.001 < (amp_meas - amp_exp) / amp_exp < 0.001, \
                "RX amplitude out-of-bound of 0.1%"
            assert -0.1 < self.wrap_phase(phs_meas - phs_exp) < 0.1, \
                "RX phase out-of-bound of 0.1 deg"


@cocotb.test(timeout_time=30, timeout_unit='us')
async def test_alsu(dut):
    tester = TestLLRF(dut, f_config='ALSU')
    await tester.test_rx()
    await tester.test_open_loop()
    await tester.test_close_loop()


@cocotb.test(timeout_time=30, timeout_unit='us')
async def test_uspas(dut):
    tester = TestLLRF(dut, f_config='USPAS')
    await tester.test_rx()
    await tester.test_open_loop()
    await tester.test_close_loop()


@cocotb.test(timeout_time=30, timeout_unit='us')
async def test_lemp(dut):
    tester = TestLLRF(dut, f_config='LEMP')
    await tester.test_rx()
    await tester.test_open_loop()
    await tester.test_close_loop()


@cocotb.test(timeout_time=30, timeout_unit='us')
async def test_awa(dut):
    tester = TestLLRF(dut, f_config='AWA')
    await tester.test_rx()
    await tester.test_open_loop()
    await tester.test_close_loop()
