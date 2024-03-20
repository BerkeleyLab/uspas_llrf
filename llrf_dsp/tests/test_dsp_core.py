import numpy as np
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from llrf_model import LLRFModel


@cocotb.test()
async def test_noniq_ddc(dut):
    f_config = cocotb.plusargs.get('f_config', 'LEMP')
    n_samples = 200
    dut._log.info("Simulating: %s, n_samples: %d", f_config, n_samples)
    model = LLRFModel(conf=f_config, n_samples=n_samples)
    clock = Clock(dut.clk, model.DSP_CLK_CYCLE, units="ns")
    cocotb.start_soon(clock.start())

    await RisingEdge(dut.clk)
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0

    amp_exp = 10000
    phs_exp = 20
    for n, (nco, sig) in enumerate(zip(
            model.gen_sinusoidal(),
            model.gen_sinusoidal(amp_exp, phs_exp))):
        await RisingEdge(dut.clk)
        dut.cosa.value = int(nco.real)
        dut.sina.value = int(nco.imag)
        dut.cav_field.value = int(sig.real)
        amp_meas = dut.amp_measured.value.integer
        amp_meas /= np.abs(model.rx.gain)
        phs_meas = dut.phs_measured.value.integer / 2**18 * 360
        phs_meas -= model.DDC_PHS_GAIN
        sig_meas = amp_meas * np.exp(1j * np.deg2rad(phs_meas))
        if n > n_samples - 5:
            dut._log.info(
                "sig mag: %8.1f cnt, phs: %6.2f deg",
                np.abs(sig_meas), np.angle(sig_meas, deg=True))
            assert np.abs(amp_meas - amp_exp) / amp_exp < 0.01, \
                "RX amplitude out-of-bound of 0.1%"
            assert np.abs(phs_meas - phs_exp) < 0.1, \
                "RX amplitude out-of-bound of 0.1 deg"
