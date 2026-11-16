import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, ReadOnly, RisingEdge

from uspas_llrf import DDS, PulseModulator

DWBB = 18
SAT_MAX = (1 << (DWBB - 1)) - 1
SAT_MIN = -(1 << (DWBB - 1))

# loop_ctrl inputs read by the model on every edge (signed ones as signed)
CFG_UNSIGNED = ['pulse_start', 'pulse_high_len', 'res_shift', 'mod_len',
                'amp_mod_enable', 'phs_mod_enable', 'amp_loop_enable',
                'amp_sin_enable', 'phs_sin_enable']
# sinusoid (dds) settings, not part of the model: its output is
SIN_CFG = ['sin_amplitude', 'sin_modulo', 'sin_phase_step_h', 'sin_phase_step_l']
CFG_SIGNED = ['amp_setpoint', 'max_amp_setpoint', 'phs_setpoint', 'phs_offset']


class TB:
    """Drives loop_ctrl on dsp_clk falling edges. A monitor steps the model on
    every rising edge with the inputs the DUT samples and checks the outputs."""

    def __init__(self, dut):
        self.dut = dut
        self.mod_aw = int(dut.MOD_AW.value)
        self.model = PulseModulator(DWBB, int(dut.PULSE_AW.value), self.mod_aw)
        self.errors = []
        self.sin_log = []  # (dds cos_out, phase_out) per dsp clock
        for name in ['trig', 'pulse_mode', 'phs_loop_enable', 'amp_loop_reset',
                     'phs_loop_reset', 'Kp_amp', 'Kp_phs', 'Ki_amp', 'Ki_phs',
                     'rx_phase_offset', 'tx_phase_offset', 'field_i', 'field_q',
                     'lb_addr', 'lb_wdata', 'lb_write_amp_mod', 'lb_write_phs_mod'] + CFG_UNSIGNED + CFG_SIGNED + SIN_CFG:
            getattr(dut, name).value = 0
        dut.max_amp_setpoint.value = SAT_MAX
        dut.dsp_reset.value = 0
        dut.drive_permit.value = 1
        cocotb.start_soon(Clock(dut.dsp_clk, 8.4, unit="ns").start())
        cocotb.start_soon(Clock(dut.lb_clk, 8, unit="ns").start())
        cocotb.start_soon(self.monitor())

    async def monitor(self):
        dut, m = self.dut, self.model
        sin = 0  # dds output before the edge, read in the previous ReadOnly
        while True:
            await RisingEdge(dut.dsp_clk)
            for name in CFG_UNSIGNED:
                setattr(m, name, int(getattr(dut, name).value))
            for name in CFG_SIGNED:
                setattr(m, name, getattr(dut, name).value.to_signed())
            drive_permit, pulse_mode = int(dut.drive_permit.value), int(dut.pulse_mode.value)
            m.step(int(dut.trig.value), sin)
            await ReadOnly()
            sin = dut.dut.sin_mod.value.to_signed()
            self.sin_log.append((sin, int(dut.dut.sin_dds.phase_out.value)))
            drive_on = m.drive_on(drive_permit, pulse_mode)
            got = {'pulse_dval': int(dut.pulse_dval.value), 'pulse_idx': int(dut.pulse_idx.value),
                   'amp_setpoint_mod': dut.amp_setpoint_mod.value.to_signed(),
                   'phs_setpoint_mod': dut.phs_setpoint_mod.value.to_signed(),
                   'drive_on': int(dut.drive_on.value)}
            exp = {'pulse_dval': m.pulse.dval, 'pulse_idx': m.pulse.idx,
                   'amp_setpoint_mod': m.amp_sp, 'phs_setpoint_mod': m.phs_sp,
                   'drive_on': drive_on}
            if not drive_on and (dut.drive_i.value.to_signed() or dut.drive_q.value.to_signed()):
                got['drive_zero'], exp['drive_zero'] = 0, 1
            if got != exp and len(self.errors) < 5:
                self.errors.append(f"t={cocotb.utils.get_sim_time('ns')} ns: got {got}, expected {exp}")

    def check(self):
        assert not self.errors, "\n".join(self.errors)

    async def configure(self, **cfg):
        """Set loop_ctrl configuration inputs on the next falling edge."""
        await FallingEdge(self.dut.dsp_clk)
        for name, value in cfg.items():
            assert name in CFG_UNSIGNED + CFG_SIGNED + SIN_CFG, name
            getattr(self.dut, name).value = value

    async def write_mod_tables(self, amp, phs):
        """Write both modulation tables through the localbus port; mirror into the model."""
        dut = self.dut
        for addr, (a, p) in enumerate(zip(amp, phs)):
            await FallingEdge(dut.lb_clk)
            dut.lb_addr.value = addr
            dut.lb_wdata.value = a & ((1 << DWBB) - 1)
            dut.lb_write_amp_mod.value = 1
            await FallingEdge(dut.lb_clk)
            dut.lb_wdata.value = p & ((1 << DWBB) - 1)
            dut.lb_write_amp_mod.value = 0
            dut.lb_write_phs_mod.value = 1
            await FallingEdge(dut.lb_clk)
            dut.lb_write_phs_mod.value = 0
        n = len(amp)
        self.model.amp_mod_table[:n] = [a & ((1 << DWBB) - 1) for a in amp]
        self.model.phs_mod_table[:n] = [p & ((1 << DWBB) - 1) for p in phs]

    async def cycle(self, trig=0, drive_permit=1, pulse_mode=0):
        """Drive one dsp_clk cycle (the monitor checks it)."""
        dut = self.dut
        await FallingEdge(dut.dsp_clk)
        dut.trig.value = trig
        dut.drive_permit.value = drive_permit
        dut.pulse_mode.value = pulse_mode

    async def pulse(self, extra=8, **kw):
        """Trigger one pulse and run until it is over."""
        dut = self.dut
        await self.cycle(trig=1, **kw)
        n = int(dut.pulse_start.value) + int(dut.pulse_high_len.value) + extra
        for _ in range(n):
            await self.cycle(**kw)
        await self.cycle()
        self.check()


def rand_table(rng, n, lo=SAT_MIN, hi=SAT_MAX):
    return [rng.randint(lo, hi) for _ in range(n)]


@cocotb.test(timeout_time=5, timeout_unit='ms')
async def test_table_rw(dut):
    """Modulation table localbus port: write, then read back on douta (1 clock latency)."""
    tb = TB(dut)
    rng = random.Random(1)
    amp, phs = rand_table(rng, 64), rand_table(rng, 64)
    await tb.write_mod_tables(amp, phs)
    for addr in range(64):
        await FallingEdge(dut.lb_clk)
        dut.lb_addr.value = addr
        await RisingEdge(dut.lb_clk)
        await ReadOnly()
        assert dut.lb_rdata_amp_mod.value.to_signed() == amp[addr]
        assert dut.lb_rdata_phs_mod.value.to_signed() == phs[addr]
    tb.check()


@cocotb.test(timeout_time=20, timeout_unit='ms')
@cocotb.parametrize(
    mod_len=[0, 1, 100, 1 << 14, (1 << 14) + 5],
    res_shift=[0, 2],
    start=[0, 7],
)
async def test_modulation(dut, mod_len, res_shift, start):
    """Amplitude and phase modulation over one pulse, including mod_len 0, 1,
    2^14 and above (saturated), res_shift > 0 and start > 0."""
    tb = TB(dut)
    rng = random.Random(mod_len * 7 + res_shift * 3 + start)
    n = min(max(mod_len, 1), 1 << tb.mod_aw)
    n_fill = min(n + 4, 1 << tb.mod_aw)
    amp, phs = rand_table(rng, n_fill, -2000, 2000), rand_table(rng, n_fill)
    await tb.write_mod_tables(amp, phs)
    high_len = min(n << res_shift, (1 << 14) + 40) + 20
    await tb.configure(pulse_start=start, pulse_high_len=high_len, res_shift=res_shift,
                       mod_len=mod_len, amp_mod_enable=1, phs_mod_enable=1,
                       amp_setpoint=10000, phs_setpoint=-5000)
    await tb.cycle()
    await tb.cycle()
    await tb.pulse()


@cocotb.test(timeout_time=5, timeout_unit='ms')
@cocotb.parametrize(amp_mod_enable=[0, 1], phs_mod_enable=[0, 1])
async def test_mod_enable(dut, amp_mod_enable, phs_mod_enable):
    """amp_mod_enable gates the amplitude table, phs_mod_enable the phase table."""
    tb = TB(dut)
    rng = random.Random(amp_mod_enable * 2 + phs_mod_enable)
    await tb.write_mod_tables(rand_table(rng, 32), rand_table(rng, 32))
    await tb.configure(pulse_start=3, pulse_high_len=40, mod_len=32,
                       amp_mod_enable=amp_mod_enable, phs_mod_enable=phs_mod_enable,
                       amp_setpoint=1000, phs_setpoint=2000)
    await tb.pulse()


@cocotb.test(timeout_time=5, timeout_unit='ms')
@cocotb.parametrize(amp_loop_enable=[0, 1])
async def test_amp_saturation(dut, amp_loop_enable):
    """Amplitude saturates at the DWBB limits; open loop also clamps to
    max_amp_setpoint, closed loop does not."""
    tb = TB(dut)
    amp = [SAT_MAX, 5000, SAT_MIN, -5000] * 4
    await tb.write_mod_tables(amp, [0] * len(amp))
    await tb.configure(pulse_start=0, pulse_high_len=24, mod_len=len(amp), amp_mod_enable=1,
                       amp_setpoint=SAT_MAX - 1000, max_amp_setpoint=100000,
                       amp_loop_enable=amp_loop_enable)
    await tb.pulse()
    await tb.configure(amp_setpoint=SAT_MIN + 1000)
    await tb.pulse()


@cocotb.test(timeout_time=5, timeout_unit='ms')
async def test_phase_wrap_offset(dut):
    """Phase wraps (no saturation) and adds phs_offset."""
    tb = TB(dut)
    phs = [SAT_MAX, 30000, SAT_MIN, -30000] * 4
    await tb.write_mod_tables([0] * len(phs), phs)
    await tb.configure(pulse_start=2, pulse_high_len=24, mod_len=len(phs), phs_mod_enable=1,
                       phs_setpoint=SAT_MAX - 1000, phs_offset=12345)
    await tb.pulse()
    await tb.configure(phs_offset=-(1 << 16))
    await tb.pulse()


@cocotb.test(timeout_time=5, timeout_unit='ms')
@cocotb.parametrize(pulse_mode=[0, 1], drive_permit=[0, 1])
async def test_drive_gate(dut, pulse_mode, drive_permit):
    """drive_on = drive_permit && (pulse_mode ? pulse_dval : 1); the drive is
    zero while off. Modulation does not depend on pulse_mode."""
    tb = TB(dut)
    rng = random.Random(pulse_mode * 2 + drive_permit)
    await tb.write_mod_tables(rand_table(rng, 16), rand_table(rng, 16))
    await tb.configure(pulse_start=4, pulse_high_len=20, mod_len=16, amp_mod_enable=1, phs_mod_enable=1,
                       amp_setpoint=3000)
    await tb.pulse(drive_permit=drive_permit, pulse_mode=pulse_mode)


@cocotb.test(timeout_time=50, timeout_unit='ms')
async def test_random(dut):
    """Random tables, configurations and triggers against the model."""
    tb = TB(dut)
    rng = random.Random(5)
    await tb.write_mod_tables(rand_table(rng, 256), rand_table(rng, 256))
    for _ in range(30):
        start, high_len = rng.randrange(20), rng.randrange(1, 300)
        await tb.configure(pulse_start=start, pulse_high_len=high_len,
                           res_shift=rng.randrange(4), mod_len=rng.randrange(260),
                           amp_mod_enable=rng.randrange(2), phs_mod_enable=rng.randrange(2),
                           amp_setpoint=rng.randint(SAT_MIN, SAT_MAX),
                           max_amp_setpoint=rng.randint(0, SAT_MAX),
                           phs_setpoint=rng.randint(SAT_MIN, SAT_MAX),
                           phs_offset=rng.randint(SAT_MIN, SAT_MAX),
                           amp_loop_enable=rng.randrange(2))
        await tb.cycle()
        await tb.cycle(trig=1)
        for _ in range(start + high_len + 10):
            await tb.cycle(trig=int(rng.random() < 0.02),
                           drive_permit=int(rng.random() < 0.9),
                           pulse_mode=rng.randrange(2))
    await tb.cycle()
    tb.check()


def sin_cfg(num, den, amp_frac=0.9):
    """dds settings for num/den of the dsp clock (32 + 12-bit phase step)
    and an amplitude amp_frac of full scale."""
    m = DDS(num=num, den=den, dwh=32, dwl=12)
    h, lo, modulo = m.calc_dds_config(dwh=32, dwl=12)
    return dict(sin_amplitude=int(amp_frac * m.full_scale_amp), sin_modulo=modulo,
                sin_phase_step_h=h, sin_phase_step_l=lo)


@cocotb.test(timeout_time=10, timeout_unit='ms')
@cocotb.parametrize(amp_sin_enable=[0, 1], phs_sin_enable=[0, 1], pulse=[0, 1])
async def test_sin_modulation(dut, amp_sin_enable, phs_sin_enable, pulse):
    """The sinusoid adds to the amplitude (saturated, clamped open loop) and
    phase (wrapped) setpoints when enabled, with or without a pulse and on
    top of the tables: CW, not gated by the pulse."""
    tb = TB(dut)
    rng = random.Random(amp_sin_enable * 4 + phs_sin_enable * 2 + pulse)
    await tb.write_mod_tables(rand_table(rng, 32, -3000, 3000), rand_table(rng, 32))
    await tb.configure(pulse_start=3, pulse_high_len=60, mod_len=32,
                       amp_mod_enable=1, phs_mod_enable=1,
                       amp_sin_enable=amp_sin_enable, phs_sin_enable=phs_sin_enable,
                       amp_setpoint=20000, phs_setpoint=SAT_MAX - 3000,
                       max_amp_setpoint=90000, **sin_cfg(7, 33))
    for _ in range(200):  # CW, no trigger
        await tb.cycle()
    if pulse:
        await tb.pulse()
    tb.check()
    sins = {s for s, _ in tb.sin_log[-150:]}
    assert len(sins) > 20 and max(sins) > 100000, "the dds is not running"


@cocotb.test(timeout_time=10, timeout_unit='ms')
@cocotb.parametrize(amp_loop_enable=[0, 1])
async def test_sin_saturation(dut, amp_loop_enable):
    """Setpoint, table entry and sinusoid near full scale: the three-term
    sum saturates at the DWBB limits, both signs."""
    tb = TB(dut)
    amp = [SAT_MAX, SAT_MIN] * 8
    await tb.write_mod_tables(amp, [0] * len(amp))
    await tb.configure(pulse_start=0, pulse_high_len=200, mod_len=len(amp), amp_mod_enable=1,
                       amp_sin_enable=1, amp_setpoint=SAT_MAX - 1000, max_amp_setpoint=100000,
                       amp_loop_enable=amp_loop_enable, res_shift=3, **sin_cfg(1, 11, 0.95))
    await tb.pulse()
    await tb.configure(amp_setpoint=SAT_MIN + 1000)
    await tb.pulse()


@cocotb.test(timeout_time=10, timeout_unit='ms')
async def test_sin_free_running(dut):
    """The sinusoid runs free: triggers (and the pulses they start) do not
    disturb its phase, which follows the phase accumulator without a jump."""
    tb = TB(dut)
    await tb.configure(phs_sin_enable=1, pulse_start=2, pulse_high_len=30, **sin_cfg(7, 33))
    trigs = (20, 157, 280)  # gaps not multiples of 33
    for k in range(400):
        await tb.cycle(trig=int(k in trigs))
    tb.check()
    phase = [p for _, p in tb.sin_log[-400:]]
    # 7/33 is exact: the phase repeats every 33 clocks, through the triggers
    assert all(phase[k + 33] == phase[k] for k in range(len(phase) - 33)), \
        "the sinusoid's phase jumped"
    assert len(set(phase)) == 33
