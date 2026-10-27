"""timing_core_local (LEMP): each of its four event codes in the EVR stream
(a data word, code in the low byte) gives one dsp_clk strobe on its own
output, other codes none; DSP_EV1 also strobes evr_event1 (evr_clk)."""
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge

CODES = [151, 152, 1, 10]  # dsp_event1..4


async def count_strobes(dut, counts):
    outs = [dut.dsp_event1, dut.dsp_event2, dut.dsp_event3, dut.dsp_event4]
    while True:
        await RisingEdge(dut.dsp_clk)
        for k, o in enumerate(outs):
            counts[k] += int(o.value)


async def count_evr_event1(dut, counts):
    while True:
        await RisingEdge(dut.evr_clk)
        counts[0] += int(dut.evr_event1.value)


@cocotb.test()
async def test_event_routing(dut):
    cocotb.start_soon(Clock(dut.lb_clk, 8, unit='ns').start())
    cocotb.start_soon(Clock(dut.evr_clk, 8.4, unit='ns').start())
    cocotb.start_soon(Clock(dut.dsp_clk, 8.4, unit='ns').start())
    dut.evr_rxd.value, dut.evr_rxk.value = 0xBC, 0b11
    await ClockCycles(dut.evr_clk, 20)
    counts, ev1 = [0] * 4, [0]
    cocotb.start_soon(count_strobes(dut, counts))
    cocotb.start_soon(count_evr_event1(dut, ev1))
    rng = random.Random(1)
    sent = [0] * 4
    for _ in range(200):
        code = rng.choice(CODES + [2, 7, 150, 153, 200])
        await FallingEdge(dut.evr_clk)
        dut.evr_rxd.value, dut.evr_rxk.value = code, 0
        await FallingEdge(dut.evr_clk)
        dut.evr_rxd.value, dut.evr_rxk.value = 0xBC, 0b11
        if code in CODES:
            sent[CODES.index(code)] += 1
        await ClockCycles(dut.evr_clk, rng.randrange(8, 30))
    await ClockCycles(dut.dsp_clk, 20)
    assert counts == sent, f"dsp_event1..4 strobes {counts}, events sent {sent}"
    assert ev1[0] == sent[0], f"evr_event1 strobes {ev1[0]}, DSP_EV1 events sent {sent[0]}"
