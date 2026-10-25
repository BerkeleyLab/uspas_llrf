import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

cocotb.log.info("Waveform tracing enabled")


@cocotb.test()
async def test_standby_mode(dut):
    """Test Standby mode (trigger_mode = 0)"""

    # Start clock
    dsp_clock = Clock(dut.dsp_clk, 8.4, unit='ns')  # ~119 MHz
    cocotb.start_soon(dsp_clock.start())

    lb_clock = Clock(dut.lb_clk, 8, unit='ns')  # 125 MHz
    cocotb.start_soon(lb_clock.start())

    # Values for testing
    standby_delay = 20

    # Reset
    dut.reset.value = 1
    dut.event_sel.value = 152  # Standby mode
    dut.trig_stb_delay.value = standby_delay
    dut.event_strobes.value = 0
    await RisingEdge(dut.dsp_clk)
    dut.reset.value = 0
    await RisingEdge(dut.dsp_clk)

    # Simulate timing message with Standby only
    # Cycle 0: Fiducial (message start)
    dut.event_strobes.value = 0b0100
    await RisingEdge(dut.dsp_clk)

    # Cycles 1-5: No events
    dut.event_strobes.value = 0b0000
    for _ in range(5):
        await RisingEdge(dut.dsp_clk)

    # Cycle 6: Standby event (event_strobes[1])
    dut.event_strobes.value = 0b0010
    await RisingEdge(dut.dsp_clk)

    # Cycle 7: No event
    dut.event_strobes.value = 0b0000
    await ClockCycles(dut.dsp_clk, 3)

    # Next cycle: Check that fiducial_int pulsed and delay is set
    assert dut.fiducial_int.value == 1, "fiducial_int should be high"
    assert dut.global_delay.value == standby_delay, f"Expected delay={standby_delay}, got {dut.global_delay.value}"

    # Next cycle: fiducial_int should be low (single pulse)
    await RisingEdge(dut.dsp_clk)
    assert dut.fiducial_int.value == 0, "fiducial_int should return to low"
    await ClockCycles(dut.dsp_clk, 3)


@cocotb.test()
async def test_accelerate_mode_with_accelerate(dut):
    """Test Accelerate mode with Accelerate event present"""

    dsp_clock = Clock(dut.dsp_clk, 8.4, unit='ns')
    cocotb.start_soon(dsp_clock.start())

    lb_clock = Clock(dut.lb_clk, 8, unit='ns')  # 125 MHz
    cocotb.start_soon(lb_clock.start())

    # Values for testing
    accelerate_delay = 10

    # Reset
    dut.reset.value = 1
    dut.event_sel.value = 151  # Accelerate mode
    dut.trig_acc_delay.value = accelerate_delay
    dut.event_strobes.value = 0
    await RisingEdge(dut.dsp_clk)
    dut.reset.value = 0
    await RisingEdge(dut.dsp_clk)

    # Simulate timing message with both Accelerate and Standby
    # Cycle 0: Fiducial
    dut.event_strobes.value = 0b0100
    await RisingEdge(dut.dsp_clk)

    # Cycles 1-4: No events
    dut.event_strobes.value = 0b0000
    for _ in range(4):
        await RisingEdge(dut.dsp_clk)

    # Cycle 5: Accelerate event (event_strobes[0])
    dut.event_strobes.value = 0b0001
    await RisingEdge(dut.dsp_clk)

    # Cycle 6: Standby event (event_strobes[1])
    dut.event_strobes.value = 0b0010
    await RisingEdge(dut.dsp_clk)

    # Cycle 7: No event
    dut.event_strobes.value = 0b00000000
    await ClockCycles(dut.dsp_clk, 3)

    # Next cycle: Should trigger on Accelerate (not Standby)
    assert dut.fiducial_int.value == 1, "fiducial_int should be high"
    assert dut.global_delay.value == accelerate_delay, f"Expected delay={accelerate_delay}, got {dut.global_delay.value}"

    await RisingEdge(dut.dsp_clk)
    assert dut.fiducial_int.value == 0, "fiducial_int should return to low"
    await ClockCycles(dut.dsp_clk, 3)


@cocotb.test()
async def test_accelerate_mode_without_accelerate(dut):
    """Test Accelerate mode falling back to Standby when Accelerate absent"""

    dsp_clock = Clock(dut.dsp_clk, 8.4, unit='ns')
    cocotb.start_soon(dsp_clock.start())

    lb_clock = Clock(dut.lb_clk, 8, unit='ns')  # 125 MHz
    cocotb.start_soon(lb_clock.start())

    # Values for testing
    accelerate_delay = 10
    standby_delay = 20

    # Reset
    dut.reset.value = 1
    dut.event_sel.value = 151  # Accelerate mode
    dut.trig_acc_delay.value = accelerate_delay
    dut.trig_stb_delay.value = standby_delay
    dut.event_strobes.value = 0
    await RisingEdge(dut.dsp_clk)
    dut.reset.value = 0
    await RisingEdge(dut.dsp_clk)

    # Simulate timing message with Standby only (no Accelerate)
    # Cycle 0: Fiducial
    dut.event_strobes.value = 0b0100
    await RisingEdge(dut.dsp_clk)

    # Cycles 1-5: No events
    dut.event_strobes.value = 0b0000
    for _ in range(5):
        await RisingEdge(dut.dsp_clk)

    # Cycle 6: Standby event only
    dut.event_strobes.value = 0b0010
    await RisingEdge(dut.dsp_clk)

    # Cycle 7: No event
    dut.event_strobes.value = 0b0000
    await ClockCycles(dut.dsp_clk, 3)

    # Next cycle: Should fall back to Standby
    assert dut.fiducial_int.value == 1, "fiducial_int should be high"
    assert dut.global_delay.value == standby_delay, f"Expected delay={standby_delay}, got {dut.global_delay.value}"

    await RisingEdge(dut.dsp_clk)
    assert dut.fiducial_int.value == 0, "fiducial_int should return to low"
    await ClockCycles(dut.dsp_clk, 100)
