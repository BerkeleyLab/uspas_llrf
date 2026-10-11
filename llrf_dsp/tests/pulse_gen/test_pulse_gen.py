import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, ReadOnly, RisingEdge


class PulseGenModel:
    """Cycle-accurate model of pulse_gen.v (registers update on each clk edge)."""

    def __init__(self, aw):
        self.aw = aw
        self.mask = (1 << aw) - 1
        self.mask1 = (1 << (aw + 1)) - 1
        self.end_val = 0
        self.pc = 0
        self.counting = 0
        self.dval = 0
        self.idx = 0

    @property
    def last(self):
        return int(self.counting and self.pc == self.end_val)

    def step(self, trigger, start, high_len, stb, res):
        is_last = self.pc == self.end_val
        in_pulse = self.counting and self.pc >= start and not is_last
        if is_last:
            counting = 0
        elif trigger:
            counting = 1
        else:
            counting = self.counting
        if not self.counting and trigger:
            pc = 0
        elif self.counting:
            pc = (self.pc + stb) & self.mask1
        else:
            pc = 0
        self.dval = int(in_pulse)
        self.idx = (((self.pc - start) & self.mask) >> res) if in_pulse else 0
        self.end_val = (start + high_len) & self.mask1
        self.pc = pc
        self.counting = counting


class TB:
    def __init__(self, dut):
        self.dut = dut
        self.aw = int(dut.AW.value)
        self.model = PulseGenModel(self.aw)
        dut.trigger.value = 0
        dut.start.value = 0
        dut.high_len.value = 0
        dut.stb_in.value = 1
        dut.res.value = 0
        cocotb.start_soon(Clock(dut.clk, 8, unit="ns").start())

    async def cycle(self, trigger=0, start=None, high_len=None, stb=1, res=None):
        """Drive inputs on the falling edge, step the model on the rising
        edge, and check pulse_dval, pulse_idx and pulse_last against it."""
        dut = self.dut
        await FallingEdge(dut.clk)
        if start is not None:
            dut.start.value = start
        if high_len is not None:
            dut.high_len.value = high_len
        if res is not None:
            dut.res.value = res
        dut.trigger.value = trigger
        dut.stb_in.value = stb
        await RisingEdge(dut.clk)
        self.model.step(trigger, int(dut.start.value), int(dut.high_len.value),
                        stb, int(dut.res.value))
        await ReadOnly()
        m = self.model
        assert int(dut.pulse_dval.value) == m.dval, "pulse_dval"
        assert int(dut.pulse_idx.value) == m.idx, "pulse_idx"
        assert int(dut.pulse_last.value) == m.last, "pulse_last"
        return int(dut.pulse_dval.value), int(dut.pulse_idx.value)


@cocotb.test(timeout_time=2, timeout_unit='us')
@cocotb.parametrize(
    start=[0, 3, 8],
    high_len=[1, 5, 10],
    res=[0, 1, 3],
)
async def test_pulse(dut, start, high_len, res):
    """One pulse: pulse_dval for high_len strobes from start, index from the
    pulse start."""
    tb = TB(dut)
    await tb.cycle(start=start, high_len=high_len, res=res)
    await tb.cycle()
    await tb.cycle(trigger=1)
    dvals, idxs = [], []
    for _ in range(start + high_len + 3):
        d, i = await tb.cycle()
        dvals.append(d)
        if d:
            idxs.append(i)
    assert sum(dvals) == high_len
    assert idxs == [ix >> res for ix in range(high_len)]


@cocotb.test(timeout_time=2, timeout_unit='us')
async def test_stb(dut):
    """The count, and so pulse_dval length and pulse_idx, advance on stb_in only."""
    tb = TB(dut)
    start, high_len = 2, 6
    await tb.cycle(start=start, high_len=high_len)
    await tb.cycle()
    await tb.cycle(trigger=1)
    stb_count = 0
    for n in range(80):
        stb = int(n % 3 == 0)
        await tb.cycle(stb=stb)
        stb_count += stb
    assert stb_count > start + high_len
    assert tb.model.counting == 0


@cocotb.test(timeout_time=2, timeout_unit='us')
async def test_retrigger(dut):
    """A trigger during a pulse does not restart it."""
    tb = TB(dut)
    await tb.cycle(start=1, high_len=8)
    await tb.cycle()
    await tb.cycle(trigger=1)
    dvals = []
    for n in range(14):
        d, _ = await tb.cycle(trigger=int(n == 4))
        dvals.append(d)
    assert sum(dvals) == 8


@cocotb.test(timeout_time=60, timeout_unit='us')
async def test_no_wrap(dut):
    """start + high_len beyond 2**AW: the pulse still lasts high_len strobes (P6)."""
    tb = TB(dut)
    full = 1 << tb.aw
    start, high_len = full - 100, 300
    assert start + high_len > full
    await tb.cycle(start=start, high_len=high_len, res=2)
    await tb.cycle()
    await tb.cycle(trigger=1)
    dvals, idxs = 0, []
    for _ in range(start + high_len + 3):
        d, i = await tb.cycle()
        dvals += d
        if d:
            idxs.append(i)
    assert dvals == high_len
    assert idxs == [ix >> 2 for ix in range(high_len)]


@cocotb.test(timeout_time=200, timeout_unit='us')
async def test_random(dut):
    """Random pulses, strobes, resolutions and triggers against the model."""
    tb = TB(dut)
    rng = random.Random(1)
    full = 1 << tb.aw
    for _ in range(40):
        start = rng.choice([0, rng.randrange(16), rng.randrange(full)])
        high_len = rng.choice([1, rng.randrange(1, 32), rng.randrange(1, full)])
        start, high_len = min(start, 600), min(high_len, 600)
        res = rng.randrange(1 << int(dut.RW.value))
        await tb.cycle(start=start, high_len=high_len, res=res)
        await tb.cycle()
        await tb.cycle(trigger=1)
        for _ in range(start + high_len + 20):
            await tb.cycle(trigger=int(rng.random() < 0.01),
                           stb=int(rng.random() < 0.8))
