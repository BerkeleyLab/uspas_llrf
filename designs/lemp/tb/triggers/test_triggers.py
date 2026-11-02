"""triggers.sv (LEMP PMOD trigger, through test_triggers.sv): after rst_n
rises the counter runs; the output is high for width clocks from
counter == delay, and low while enable is low."""
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, ReadOnly, RisingEdge


async def pulse(dut, delay, width, n_cycles):
    """Release rst_n and return the output on each clock after the release."""
    await FallingEdge(dut.clk)
    dut.delay.value, dut.width.value = delay, width
    dut.enable.value, dut.rst_n.value = 1, 0
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1
    out = []
    for _ in range(n_cycles):
        await RisingEdge(dut.clk)
        await ReadOnly()
        out.append(int(dut.pmod_trigs.value))
    return out


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
