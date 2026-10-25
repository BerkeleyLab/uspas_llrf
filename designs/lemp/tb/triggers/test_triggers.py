"""triggers.v (LEMP PMOD trigger): after rst_n rises the counter runs; the
output is high for width clocks from counter == global_delay + delay, and
low while enable is low."""
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, ReadOnly, RisingEdge


async def pulse(dut, global_delay, delay, width, n_cycles):
    """Release rst_n and return the output on each clock after the release."""
    await FallingEdge(dut.clk)
    dut.global_delay.value, dut.delay.value, dut.width.value = global_delay, delay, width
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
        gd, d, w = rng.randrange(20), rng.randrange(20), rng.randrange(1, 15)
        out = await pulse(dut, gd, d, w, gd + d + w + 10)
        # the first clock after the release compares counter 0; the output is
        # registered from that compare
        exp = [int(gd + d <= k < gd + d + w) for k in range(len(out))]
        assert out == exp, f"global_delay {gd} delay {d} width {w}: {out}"


@cocotb.test()
async def test_disable(dut):
    cocotb.start_soon(Clock(dut.clk, 8, unit='ns').start())
    out = await pulse(dut, 0, 2, 50, 10)
    assert out[5] == 1
    await FallingEdge(dut.clk)
    dut.enable.value = 0
    await RisingEdge(dut.clk)
    await ReadOnly()
    assert int(dut.pmod_trigs.value) == 0
