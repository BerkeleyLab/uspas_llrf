"""triggers.sv (LEMP PMOD trigger, through test_triggers.sv): a one-shot
armed by rst_n. After rst_n rises the counter runs; the output is high for
width clocks from counter == delay, and low while enable is low. Width 0
gives no pulse, enabling alone fires nothing, and rst_n during a pulse
restarts it."""
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, ReadOnly, RisingEdge


async def sample(dut, n_cycles):
    """The output on each of the next n_cycles clocks."""
    out = []
    for _ in range(n_cycles):
        await RisingEdge(dut.clk)
        await ReadOnly()
        out.append(int(dut.pmod_trigs.value))
    return out


async def idle(dut):
    """Start a test disabled, so no state carries over from the last one
    (the tests share one simulation)."""
    cocotb.start_soon(Clock(dut.clk, 8, unit='ns').start())
    await FallingEdge(dut.clk)
    dut.enable.value, dut.rst_n.value = 0, 1
    await FallingEdge(dut.clk)


async def fire(dut):
    """One clock of rst_n low (a wave_trig in the LEMP shell)."""
    await FallingEdge(dut.clk)
    dut.rst_n.value = 0
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1


async def pulse(dut, delay, width, n_cycles):
    """Enable, trigger and return the output on each clock after the release."""
    await FallingEdge(dut.clk)
    dut.delay.value, dut.width.value = delay, width
    dut.enable.value = 1
    await fire(dut)
    return await sample(dut, n_cycles)


@cocotb.test()
async def test_delay_width(dut):
    cocotb.start_soon(Clock(dut.clk, 8, unit='ns').start())
    dut.enable.value, dut.rst_n.value = 0, 0
    rng = random.Random(1)
    for _ in range(8):
        d, w = rng.randrange(40), rng.randrange(1, 15)
        out = await pulse(dut, d, w, d + w + 10)
        # the first clock after the release compares counter 0; the output is
        # registered from that compare
        exp = [int(d <= k < d + w) for k in range(len(out))]
        assert out == exp, f"delay {d} width {w}: {out}"


@cocotb.test()
async def test_disable(dut):
    cocotb.start_soon(Clock(dut.clk, 8, unit='ns').start())
    out = await pulse(dut, 2, 50, 10)
    assert out[5] == 1
    await FallingEdge(dut.clk)
    dut.enable.value = 0
    await RisingEdge(dut.clk)
    await ReadOnly()
    assert int(dut.pmod_trigs.value) == 0


@cocotb.test()
async def test_width_zero(dut):
    """Width 0 gives no pulse (on the LEMP branch the output stayed high
    until enable dropped), and the next trigger with a width works."""
    await idle(dut)
    out = await pulse(dut, 3, 0, 40)
    assert not any(out), f"width 0: {out}"
    await FallingEdge(dut.clk)
    dut.width.value = 4
    await fire(dut)
    out = await sample(dut, 20)
    assert out == [int(3 <= k < 7) for k in range(20)], f"after width 0: {out}"


@cocotb.test()
async def test_no_fire_on_enable(dut):
    """Enabling arms nothing: no output until a trigger. On the LEMP branch
    the counter ran whenever enabled, so it fired delay clocks after enable
    at power-up (counter 0), and a trigger disabled before its delay fired
    once re-enabled. After a pulse the counter stops, so it does not fire
    again without a trigger."""
    await idle(dut)
    await FallingEdge(dut.clk)
    dut.delay.value, dut.width.value = 5, 4
    dut.enable.value = 1
    out = await sample(dut, 40)
    assert not any(out), f"fired on enable: {out}"
    await fire(dut)
    out = await sample(dut, 60)
    assert out == [int(5 <= k < 9) for k in range(60)], f"after trigger: {out}"
    # a trigger disabled before its delay and enabled again: nothing until
    # the next trigger (the power-up case does not depend on earlier tests)
    await FallingEdge(dut.clk)
    dut.delay.value = 30
    await fire(dut)
    await sample(dut, 5)
    await FallingEdge(dut.clk)
    dut.enable.value = 0
    await FallingEdge(dut.clk)
    dut.enable.value = 1
    out = await sample(dut, 60)
    assert not any(out), f"fired on re-enable: {out}"


@cocotb.test()
async def test_retrigger(dut):
    """A trigger during a pulse ends it and restarts the count: the output is
    low on the clock after the trigger and high again delay clocks later,
    for a full width (on the LEMP branch the pulse ran on to the new end)."""
    await idle(dut)
    delay, width, k_retrig = 2, 20, 8
    out = await pulse(dut, delay, width, k_retrig)
    assert out == [int(delay <= k < delay + width) for k in range(k_retrig)], out
    await fire(dut)
    out = await sample(dut, delay + width + 10)
    exp = [int(delay <= k < delay + width) for k in range(len(out))]
    assert out == exp, f"retrigger: {out}"
