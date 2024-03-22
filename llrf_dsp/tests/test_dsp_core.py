import numpy as np
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from llrf_model import LLRFModel
from llrf_dsp import CORDIC_GAIN
import logging


def wrap_phase(p):
    return (p + 180) % 360 - 180


async def test_noniq_ddc(dut, f_config='USPAS'):
    dut._log.setLevel(logging.INFO)
    n_samples = 220
    model = LLRFModel(conf=f_config, n_samples=n_samples)
    dut._log.info("Simulating: %s, n_samples: %d", f_config, n_samples)
    dut._log.info(f'LLRFModel RX: {model.rx}')
    dut._log.info(f'LLRFModel TX: {model.tx}')

    clock = Clock(dut.clk, model.DSP_CLK_CYCLE, units="ns")
    cocotb.start_soon(clock.start())

    await RisingEdge(dut.clk)
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0

    dut.rx_phase_offset.value = int(model.RX_LO_PHS_DEG / 360 * 2**19)
    dut.tx_phase_offset.value = int(model.TX_LO_PHS_DEG / 360 * 2**19)

    amp_exp = (1 << 15) / np.abs(model.rx.gain) * 3.9
    phs_exp = wrap_phase(np.random.random() * 360)
    dut._log.info(
        f"expected mag: {amp_exp:8.1f} cnt, phs: {phs_exp:6.2f} deg")

    for n, (nco, sig) in enumerate(zip(
            model.gen_sinusoidal(),
            model.gen_sinusoidal(amp_exp, phs_exp))):
        await RisingEdge(dut.clk)
        nco *= CORDIC_GAIN
        dut.cosa.value = int(nco.real)
        dut.sina.value = int(nco.imag)
        dut.cav_field.value = int(sig.real)

        i_meas = dut.field_i.value.signed_integer
        q_meas = dut.field_q.value.signed_integer
        iq_meas = i_meas + 1j * q_meas
        amp_meas = dut.amp_measured.value.signed_integer
        amp_meas /= np.abs(model.rx.gain)
        phs_meas = dut.phs_measured.value.signed_integer / 2**18 * 360
        if n > n_samples - 5:
            dut._log.debug(
                "raw IQ   mag: %8.1f cnt, phs: %6.2f deg",
                np.abs(iq_meas), np.angle(iq_meas, deg=True))
            dut._log.info(
                "measured mag: %8.1f cnt, phs: %6.2f deg",
                amp_meas, phs_meas)

            assert -0.1 < (amp_meas - amp_exp) / amp_exp < 0.01, \
                "RX amplitude out-of-bound of 0.1%"
            assert -0.1 < wrap_phase(phs_meas - phs_exp) < 0.1, \
                "RX phase out-of-bound of 0.1 deg"


@cocotb.test()
async def test_noniq_ddc_alsu(dut):
    await test_noniq_ddc(dut, f_config='ALSU')


@cocotb.test()
async def test_noniq_ddc_uspas(dut):
    await test_noniq_ddc(dut, f_config='USPAS')


@cocotb.test()
async def test_noniq_ddc_lemp(dut):
    await test_noniq_ddc(dut, f_config='LEMP')

