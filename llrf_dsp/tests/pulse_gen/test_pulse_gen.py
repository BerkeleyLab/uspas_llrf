import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


class TB:
    def __init__(self, dut, start=0, high_len=5):
        self.dut = dut
        dut.start.value = start
        dut.high_len.value = high_len
        dut.stb_in.value = 1
        cocotb.start_soon(Clock(dut.clk, 8, unit="ns").start())

    async def trigger(self):
        for val in [0, 1, 0]:
            self.dut.trigger.value = val
            await RisingEdge(self.dut.clk)


@cocotb.test(timeout_time=1, timeout_unit='us')
@cocotb.parametrize(
    start=[0, 3, 8],
    high_len=[1, 5, 10]
)
async def test(dut, start, high_len):
    tb = TB(dut, start, high_len)
    await tb.trigger()
    await RisingEdge(dut.clk)
    for ix in range(start + high_len):
        v = dut.pulse_dval.value
        cocotb.log.debug(f'pulse_dval: {v}, ix {ix}')
        assert v == (start <= ix)
        await RisingEdge(dut.clk)
    assert dut.pulse_dval.value == 0
