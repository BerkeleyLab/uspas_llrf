import numpy as np
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from llrf_model import LLRFModel
from cocotb.handle import SimHandleBase
import logging


class TestLLRF:
    def __init__(self, dut: SimHandleBase,  f_config='USPAS') -> None:
        self.dut = dut
        self.n_samples = 220
        self.llrf = LLRFModel(conf=f_config, n_samples=self.n_samples)
        dut._log.setLevel(logging.INFO)
        dut._log.info(f"Simulating: {f_config}")
        dut._log.info(f'LLRFModel RX:\n{self.llrf.rx}')
        dut._log.info(f'LLRFModel TX:\n{self.llrf.tx}')
        self._coro = None

    def start(self) -> None:
        if self._coro is not None:
            raise RuntimeError("Coroutine already started")
        self._coro = cocotb.start_soon(self._run())

    def stop(self) -> None:
        if self._coro is None:
            raise RuntimeError("Coroutine never started")
        self._coro.kill()
        self._coro = None

    async def _run(self) -> None:
        clock = Clock(self.dut.clk, self.llrf.DSP_CLK_CYCLE, units="ns")
        cocotb.start_soon(clock.start())
        await RisingEdge(self.dut.clk)
        self.dut.reset.value = 1
        await RisingEdge(self.dut.clk)
        self.dut.reset.value = 0
        cocotb.start_soon(self.drive_dds())
        cocotb.start_soon(self.task_ddc_check())

    async def drive_dds(self):
        for nco in self.llrf.gen_sinusoidal():
            await RisingEdge(self.dut.clk)
            nco *= self.llrf.CORDIC_GAIN
            self.dut.cosa.value = int(nco.real)
            self.dut.sina.value = int(nco.imag)

    async def task_ddc_check(self):
        # llrf = LLRFModel(conf=f_config, n_samples=n_samples)
        dut = self.dut
        llrf = self.llrf
        dut.rx_phase_offset.value = llrf.encode_phase(
            llrf.rx.phase_off_deg, width=len(dut.rx_phase_offset))
        dut.tx_phase_offset.value = 0  # TBD

        amp_exp = (1 << 15) / np.abs(llrf.rx.gain) * 3.9
        phs_exp = llrf.wrap_phase(np.random.random() * 360)
        dut._log.info(
            f"expected mag: {amp_exp:8.1f} cnt, phs: {phs_exp:6.2f} deg")

        for n, sig in enumerate(llrf.gen_sinusoidal(amp_exp, phs_exp)):
            await RisingEdge(dut.clk)
            dut.cav_field.value = int(sig.real)

            i_meas = dut.field_i.value.signed_integer
            q_meas = dut.field_q.value.signed_integer
            iq_meas = i_meas + 1j * q_meas
            amp_meas = dut.amp_measured.value.signed_integer
            amp_meas /= np.abs(llrf.rx.gain)
            phs_meas = llrf.decode_phase(
                dut.phs_measured.value.signed_integer,
                width=len(dut.phs_measured))
            if n > self.n_samples - 5:
                dut._log.debug(
                    "raw IQ   mag: %8.1f cnt, phs: %6.2f deg",
                    np.abs(iq_meas), np.angle(iq_meas, deg=True))
                dut._log.info(
                    "measured mag: %8.1f cnt, phs: %6.2f deg",
                    amp_meas, phs_meas)

                assert -0.1 < (amp_meas - amp_exp) / amp_exp < 0.01, \
                    "RX amplitude out-of-bound of 0.1%"
                assert -0.1 < llrf.wrap_phase(phs_meas - phs_exp) < 0.1, \
                    "RX phase out-of-bound of 0.1 deg"


@cocotb.test()
async def test_rx_alsu(dut):
    tester = TestLLRF(dut, f_config='ALSU')
    tester.start()
    tester.stop()


@cocotb.test()
async def test_rx_uspas(dut):
    tester = TestLLRF(dut, f_config='USPAS')
    tester.start()
    tester.stop()


@cocotb.test()
async def test_rx_lemp(dut):
    tester = TestLLRF(dut, f_config='LEMP')
    tester.start()
    tester.stop()
