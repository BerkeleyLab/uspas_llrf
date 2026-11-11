"""rx_chain monitor path: DC_CH_MASK channels (here 6 and 7, as LEMP) give
I = ADC << 2, Q = 0 on the monitor outputs, without delay, while the loop
outputs stay the DDC; the other channels' monitor outputs are the DDC."""
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

N_ADC, DW, DWBB = 8, 16, 18
DC_CH = (6, 7)


def lane(flat, ch, w=DWBB):
    return (flat >> (w * ch)) & ((1 << w) - 1)


@cocotb.test()
async def test_dc_channels(dut):
    cocotb.start_soon(Clock(dut.dsp_clk, 8, unit="ns").start())
    dut.dsp_reset.value = 1
    dut.adc_data_in.value = 0
    dut.dds_amplitude.value = 79590      # full scale after the CORDIC gain
    dut.dds_phase_shift.value = 0
    dut.dds_phase_step.value = (0x1745d << 12) | 0x2e8   # ~4/11
    dut.dds_modulo.value = 4
    for _ in range(3):
        await RisingEdge(dut.dsp_clk)
    dut.dsp_reset.value = 0
    rng = random.Random(1)
    lo, dc_loop_differs = set(), 0
    for cycle in range(400):
        await FallingEdge(dut.dsp_clk)
        adc = [rng.randrange(1 << DW) for _ in range(N_ADC)]
        dut.adc_data_in.value = sum(a << (DW * ch) for ch, a in enumerate(adc))
        await Timer(1, unit="ns")
        sig_i, sig_q = int(dut.sig_i_flat.value), int(dut.sig_q_flat.value)
        mon_i, mon_q = int(dut.mon_i_flat.value), int(dut.mon_q_flat.value)
        lo.add(int(dut.lo_cos.value))
        for ch in range(N_ADC):
            if ch in DC_CH:
                assert lane(mon_i, ch) == adc[ch] << 2, f"cycle {cycle} ch {ch}: mon_i"
                assert lane(mon_q, ch) == 0, f"cycle {cycle} ch {ch}: mon_q"
                dc_loop_differs += lane(sig_i, ch) != lane(mon_i, ch)
            else:
                assert lane(mon_i, ch) == lane(sig_i, ch), f"cycle {cycle} ch {ch}: mon_i"
                assert lane(mon_q, ch) == lane(sig_q, ch), f"cycle {cycle} ch {ch}: mon_q"
    assert dc_loop_differs > 300, "DC channels' loop outputs should stay the DDC"
    assert len(lo) > 2, "RX LO not exported"
