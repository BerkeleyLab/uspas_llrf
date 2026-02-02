import numpy as np
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer
from cocotb.handle import Immediate
from cocotb.handle import SimHandleBase
from uspas_llrf.llrf_model.llrf_dsp import LLRF_DSP, wrap_phase, \
    default_configs
from uspas_llrf.llrf_model.plant import Plant
import itertools
import random
import logging


class TB:
    def __init__(self, dut: SimHandleBase, f_config='USPAS'):
        dut._log.setLevel(logging.INFO)
        self.dut = dut
        dsp_config = default_configs[f_config]
        # override tx dds setting for loopback test at IF_adc, no upsampling
        dsp_config['TX_NUM_DDS'] = dsp_config['NUM_DDS']
        dsp_config['TX_DEN_DDS'] = dsp_config['DEN_DDS']
        dsp_config['TX_SECOND_NYQUIST'] = False
        self.llrf = llrf = LLRF_DSP(dsp_config)
        self.plant = Plant(
            conf=f_config, settings_fname='cavity.json', llrf=llrf)
        self.log_banner(f'Simulating: {f_config}')
        cocotb.log.info(f'LLRFModel:\n{llrf}')
        rx_phase_off_reg = self.llrf.encode_phase(
            llrf.cal_factors.rx_phase_off_deg)
        tx_phase_off_reg = self.llrf.encode_phase(
            llrf.cal_factors.tx_phase_off_deg)
        self.dut.rx_phase_offset.value = rx_phase_off_reg
        self.dut.tx_phase_offset.value = tx_phase_off_reg
        cocotb.log.info(
            f'RX phase off: {llrf.cal_factors.rx_phase_off_deg:8.2f} deg; '
            f'TX phase off: {llrf.cal_factors.tx_phase_off_deg:8.2f} deg')
        cocotb.log.debug(
            f'RX phase off: {rx_phase_off_reg:8d} cnt; '
            f'TX phase off: {tx_phase_off_reg:8d} cnt')
        clock = Clock(self.dut.clk, llrf.DSP_CLK_CYCLE, unit="ns")
        cocotb.start_soon(clock.start())

    def log_banner(self, str):
        cocotb.log.info('*'*20 + f"{str:^20s}" + '*'*20)

    async def init_test(self, amp_exp=None, phs_exp=None):
        await self.reset_dut()
        # scramble internal init states of dut:
        await ClockCycles(self.dut.clk, random.randint(0, 20))
        if amp_exp is None:
            amp_exp = self.llrf.cal_factors.max_adc_input
        else:
            assert amp_exp < self.llrf.cal_factors.max_adc_input, \
                f"amp_exp {amp_exp:.3f} too high. " \
                f"max value : {self.llrf.cal_factors.max_adc_input:.3f}"
        if phs_exp is None:
            phs_exp = wrap_phase(random.random() * 360)
        cocotb.start_soon(self.drive_dds())
        return amp_exp, phs_exp

    async def test_rx(self, amp_exp=None, phs_exp=None, wait=200):
        self.log_banner('RX Test')
        cocotb.log.info(f'LLRFModel RX:\n{self.llrf.rx}')
        amp_exp, phs_exp = await self.init_test(amp_exp, phs_exp)
        cocotb.start_soon(self.drive_adc(amp_exp, phs_exp))
        await ClockCycles(self.dut.clk, wait)  # settling time of filters
        await self.check_sig(amp_exp, phs_exp)

    async def test_open_loop(self, amp_exp=None, phs_exp=None, wait=320):
        self.log_banner('Open Loop Test')
        cocotb.log.info(f'LLRFModel TX:\n{self.llrf.tx}')

        amp_exp, phs_exp = await self.init_test(amp_exp, phs_exp)
        amp_setp, phs_setp = self.llrf.calc_open_loop_setp(amp_exp, phs_exp)
        self.dut.amp_setpoint.value = amp_setp
        self.dut.phs_setpoint.value = phs_setp
        cocotb.start_soon(self.loopback())
        await ClockCycles(self.dut.clk, wait)  # settling time
        await self.check_sig(amp_exp, phs_exp)

    async def test_close_loop(self, amp_exp=None, phs_exp=None, wait=2020):
        self.log_banner('Close Loop Test')
        cocotb.log.info(f'Cavity Model:\n{self.plant.cav}')

        amp_exp, phs_exp = await self.init_test(amp_exp, phs_exp)
        amp_setp, phs_setp = self.llrf.calc_close_loop_setp(amp_exp, phs_exp)
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
        self.dut.amp_setpoint.value = amp_setp
        self.dut.phs_setpoint.value = phs_setp
        self.dut.amp_loop_reset.value = 1
        self.dut.phs_loop_reset.value = 1
        self.dut.Kp_amp.value = 20
        self.dut.Kp_phs.value = 20
        self.dut.Ki_amp.value = 50
        self.dut.Ki_phs.value = 200
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
            self.dut.adc_in.set(Immediate(
                self.dut.dac_out.value.to_signed()))

    async def feedback(self) -> None:
        while True:
            await self.plant.i_queue.put(self.dut.dac_out.value.to_signed())
            await Timer(2, 'ns')  # delay by cable
            y = int(await self.plant.o_queue.get())
            self.dut.adc_in.value = min(max(y, -32678), 32767)

    async def check_sig(self, amp_exp, phs_exp) -> None:
        cocotb.log.warning(
            f"expected mag: {amp_exp:8.2f} cnt,  phs: {phs_exp:6.3f} deg")
        for _ in range(5):
            await RisingEdge(self.dut.clk)
            i_meas = self.dut.field_i.value.to_signed()
            q_meas = self.dut.field_q.value.to_signed()
            iq_meas = i_meas + 1j * q_meas
            amp_meas = self.dut.amp_measured.value.to_signed()
            amp_meas /= np.abs(self.llrf.rx.gain)
            phs_sig = self.dut.phs_measured
            phs_meas = self.llrf.decode_phase(
                phs_sig.value.to_signed(), width=len(phs_sig))
            cocotb.log.debug(
                f"raw IQ   mag: {np.abs(iq_meas):8.2f} cnt,  "
                f"phs: {np.angle(iq_meas, deg=True):6.3f} deg")
            cocotb.log.warning(
                f"measured mag: {amp_meas:8.2f} cnt,  "
                f"phs: {phs_meas:6.3f} deg")
            amp_err = abs(amp_meas - amp_exp) / amp_exp
            assert amp_err < 0.001, "amplitude out-of-bound of 0.1%"
            phs_err = abs(wrap_phase(phs_meas - phs_exp))
            assert phs_err < 0.1, "phase out-of-bound of 0.1 deg"


@cocotb.test(timeout_time=30, timeout_unit='us')
@cocotb.parametrize(
    amp_exp=[5000, 15000],
    phs_exp=[-100, 45, 270]
)
async def test_alsu(dut, amp_exp, phs_exp):
    tester = TB(dut, f_config='ALSU')
    await tester.test_rx(amp_exp, phs_exp)
    await tester.test_open_loop(amp_exp, phs_exp)
    await tester.test_close_loop(amp_exp, phs_exp)


@cocotb.test(timeout_time=30, timeout_unit='us')
@cocotb.parametrize(
    amp_exp=[5000, 15000],
    phs_exp=[-100, 45, 270]
)
async def test_uspas(dut, amp_exp, phs_exp):
    tester = TB(dut, f_config='USPAS')
    await tester.test_rx(amp_exp, phs_exp)
    await tester.test_open_loop(amp_exp, phs_exp)
    await tester.test_close_loop(amp_exp, phs_exp)


@cocotb.test(timeout_time=30, timeout_unit='us')
@cocotb.parametrize(
    amp_exp=[5000, 15000],
    phs_exp=[-100, 45, 270]
)
async def test_lemp(dut, amp_exp, phs_exp):
    tester = TB(dut, f_config='LEMP')
    await tester.test_rx(amp_exp, phs_exp)
    await tester.test_open_loop(amp_exp, phs_exp)
    await tester.test_close_loop(amp_exp, phs_exp)


@cocotb.test(timeout_time=30, timeout_unit='us')
@cocotb.parametrize(
    amp_exp=[5000, 15000],
    phs_exp=[-100, 45, 270]
)
async def test_awa(dut, amp_exp, phs_exp):
    tester = TB(dut, f_config='AWA')
    await tester.test_rx(amp_exp, phs_exp)
    await tester.test_open_loop(amp_exp, phs_exp)
    await tester.test_close_loop(amp_exp, phs_exp)
