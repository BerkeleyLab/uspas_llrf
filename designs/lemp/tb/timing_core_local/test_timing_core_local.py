"""timing_core_local (LEMP): each of its four event codes in the EVR stream
(a data word, code in the low byte) gives one dsp_clk strobe on its own
output, other codes none; DSP_EV1 also strobes evr_event1 (evr_clk). After
each fiducial (1), the EVR trigger fires once at the end of the window if
accelerate (151) or standby (152) came, per event_sel, with its delay."""
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


async def start(dut):
    cocotb.start_soon(Clock(dut.lb_clk, 8, unit='ns').start())
    cocotb.start_soon(Clock(dut.evr_clk, 8.4, unit='ns').start())
    cocotb.start_soon(Clock(dut.dsp_clk, 8.4, unit='ns').start())
    dut.evr_rxd.value, dut.evr_rxk.value = 0xBC, 0b11
    dut.event_sel.value, dut.trig_acc_delay.value, dut.trig_stb_delay.value = 0, 0, 0


async def send(dut, code):
    await FallingEdge(dut.evr_clk)
    dut.evr_rxd.value, dut.evr_rxk.value = code, 0
    await FallingEdge(dut.evr_clk)
    dut.evr_rxd.value, dut.evr_rxk.value = 0xBC, 0b11


@cocotb.test()
async def test_event_routing(dut):
    await start(dut)
    await ClockCycles(dut.evr_clk, 20)
    counts, ev1 = [0] * 4, [0]
    cocotb.start_soon(count_strobes(dut, counts))
    cocotb.start_soon(count_evr_event1(dut, ev1))
    rng = random.Random(1)
    sent = [0] * 4
    for _ in range(200):
        code = rng.choice(CODES + [2, 7, 150, 153, 200])
        await send(dut, code)
        if code in CODES:
            sent[CODES.index(code)] += 1
        await ClockCycles(dut.evr_clk, rng.randrange(8, 30))
    await ClockCycles(dut.dsp_clk, 20)
    assert counts == sent, f"dsp_event1..4 strobes {counts}, events sent {sent}"
    assert ev1[0] == sent[0], f"evr_event1 strobes {ev1[0]}, DSP_EV1 events sent {sent[0]}"


@cocotb.test()
async def test_evr_trig(dut):
    """One EVR trigger per fiducial message: accelerate mode (event_sel 151)
    takes 151 if it came, else 152; standby mode (152) only 152; any other
    event_sel never fires. evr_delay is the matching mode delay."""
    await start(dut)
    acc, stb = 300, 120
    dut.trig_acc_delay.value, dut.trig_stb_delay.value = acc, stb
    window = int(dut.EVR_TRIG_WINDOW.value)
    cases = [(151, [151, 152], acc), (151, [152], stb), (151, [], None), (152, [151, 152], stb),
             (152, [151], None), (0, [151, 152], None), (1, [151, 152], None)]
    for event_sel, codes, delay in cases:
        dut.event_sel.value = event_sel
        fired, t_fire = 0, None
        await send(dut, 1)
        for c in codes:
            await ClockCycles(dut.evr_clk, 5)
            await send(dut, c)
        for t in range(window + 40):
            await RisingEdge(dut.dsp_clk)
            if int(dut.evr_trig.value):
                fired, t_fire = fired + 1, t
                got = int(dut.evr_delay.value)
        name = f"event_sel {event_sel}, events {codes}"
        if delay is None:
            assert not fired, f"{name}: fired"
            continue
        assert fired == 1, f"{name}: fired {fired} times"
        assert got == delay, f"{name}: evr_delay {got}, expected {delay}"
        assert window - 20 <= t_fire <= window + 20, f"{name}: fired {t_fire} clocks after the message"
