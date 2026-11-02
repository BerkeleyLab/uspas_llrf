import itertools
import random

import cocotb
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge

from uspas_llrf import WaveTrigSel
from uspas_llrf.tests.test_llrf_shell import TB_llrf_shell as TB_base


EV_ACCL, EV_STBY, EV_FIDU, EV_TS = 151, 152, 1, 10  # evr_events[0..3]


class TB_llrf_shell(TB_base):
    """The base TB on the LEMP shell: ADC 6 and 7 are the beam voltage and
    current (DC channels), and the drives are armed by a fiducial."""

    def __init__(self, dut, **kwargs):
        super().__init__(dut, dc_adcs=(6, 7), **kwargs)

    async def write_init_regs(self):
        await super().write_init_regs()
        await self.arm_dac_permit()

    async def arm_dac_permit(self):
        """The DAC permit latch enables the drives (soft_driveN_enable) on a
        fiducial rising edge; with fiducial_sel 0 the fiducial is wave_trig,
        fired here by a software trigger."""
        await self.lb.write_reg('wave_trig_sel', int(WaveTrigSel.Software))
        await self.lb.write_reg('soft_trigger', 1)
        await ClockCycles(self.dut.dsp_clk, 50)
        await self.lb.write_reg('wave_trig_sel', int(self.llrf.init_regs.wave_trig_sel))

    def sig(self, name):
        return getattr(self.dut.llrf_shell, name)

    async def soft_trigger(self, n_after=0):
        await self.lb.write_reg('soft_trigger', 1)
        await ClockCycles(self.dut.dsp_clk, n_after)

    # --- EVR stream: idle K characters, an event code is one data word
    async def evr_idle(self):
        await FallingEdge(self.dut.gt_rxclk)
        self.dut.gt_rxdata.value, self.dut.gt_rxcharisk.value = 0xBC, 0b11

    async def send_event(self, code):
        await FallingEdge(self.dut.gt_rxclk)
        self.dut.gt_rxdata.value, self.dut.gt_rxcharisk.value = code, 0
        await self.evr_idle()


@cocotb.test(timeout_time=600, timeout_unit='us')
@cocotb.parametrize(
    amp_exp=[15000, 30000],
    phs_exp=[-100, 45, 270]
)
async def test(dut, amp_exp, phs_exp, loop='loop0'):
    tb = TB_llrf_shell(
        dut,
        f_config='LEMP',
        wave_samp_per=random.randint(1, 8),
        amp_exp=amp_exp, phs_exp=phs_exp,
        regmap_json_path='../../llrf_shell.json')
    await tb.test_open_loop(loop)
    await tb.test_fast_interlock(loop)
    await tb.test_close_loop(loop)


@cocotb.test(timeout_time=200, timeout_unit='us')
@cocotb.parametrize(loop=['loop0', 'loop1'])
async def test_pulse_modulation(dut, loop):
    tb = TB_llrf_shell(dut, f_config='LEMP', regmap_json_path='../../llrf_shell.json')
    await tb.test_pulse_modulation(loop)


@cocotb.test(timeout_time=100, timeout_unit='us')
async def test_buf_delay(dut):
    tb = TB_llrf_shell(dut, f_config='LEMP', regmap_json_path='../../llrf_shell.json')
    await tb.test_buf_delay()


@cocotb.test(timeout_time=400, timeout_unit='us')
async def test_dc(dut):
    """ADC 6 and 7 (beam voltage and current) are DC channels: their I
    buffers hold the ADC sample << 2 and their Q buffers 0 (plan L1)."""
    tb = TB_llrf_shell(dut, f_config='LEMP', regmap_json_path='../../llrf_shell.json')
    await tb.write_init_regs()
    for v in range(-30000, 30001, 9000):
        dc = {6: v, 7: -v // 2}
        for ch, x in dc.items():
            dut.adc_array_in[ch].value = x
        for ch, x in dc.items():
            await tb.read_sig_buf(f'adc{ch}_i_buf')  # capture from before the step
            i_buf = await tb.read_sig_buf(f'adc{ch}_i_buf')
            q_buf = await tb.read_sig_buf(f'adc{ch}_q_buf')
            assert (i_buf == x * 4).all(), f"adc{ch}_i_buf {set(i_buf)} for DC {x}"
            assert (q_buf == 0).all(), f"adc{ch}_q_buf {set(q_buf)} for DC {x}"


@cocotb.test(timeout_time=50, timeout_unit='us')
async def test_sssb(dut):
    """SSSB outputs are the inverted registers; its inputs read as status."""
    tb = TB_llrf_shell(dut, f_config='LEMP', regmap_json_path='../../llrf_shell.json')
    for sw, rst in ((1, 0), (0, 1), (1, 1), (0, 0)):
        await tb.lb.write_reg('sssb_rf_switch', sw)
        await tb.lb.write_reg('sssb_rst', rst)
        await ClockCycles(dut.dsp_clk, 20)
        assert (int(dut.sssb_rf_switch_out.value), int(dut.sssb_rst_out.value)) == (1 - sw, 1 - rst)
    for alarm, status in ((1, 0), (0, 1)):
        dut.sssb_alarm.value, dut.sssb_rf_status.value = alarm, status
        await ClockCycles(dut.lb_clk, 4)
        assert await tb.lb.read_reg('sssb_alarm') == alarm
        assert await tb.lb.read_reg('sssb_rf_status') == status


@cocotb.test(timeout_time=100, timeout_unit='us')
async def test_dac_permit(dut):
    """Any latched interlock turns both drives off at once; with none latched,
    a fiducial rising edge re-arms each drive from soft_driveN_enable (a
    changed enable takes effect at the next fiducial)."""
    tb = TB_llrf_shell(dut, f_config='LEMP', regmap_json_path='../../llrf_shell.json')
    await tb.write_init_regs()  # CW, both enables 1, armed
    await tb.lb.write_reg('wave_trig_sel', int(WaveTrigSel.Software))
    lc = [tb.sig('loops').gen_loops[n].loop_ctrl for n in range(2)]

    async def drive_on():
        await ClockCycles(dut.dsp_clk, 4)
        return [int(c.drive_on.value) for c in lc]

    assert await drive_on() == [1, 1]
    dut.intlk_latch_in.value = 0b100
    assert await drive_on() == [0, 0]
    dut.intlk_latch_in.value = 0
    await ClockCycles(dut.dsp_clk, 100)
    assert await drive_on() == [0, 0], "re-armed without a fiducial"
    dut.intlk_latch_in.value = 0b1
    await tb.soft_trigger(20)
    assert await drive_on() == [0, 0], "re-armed while latched"
    dut.intlk_latch_in.value = 0
    await tb.soft_trigger(20)
    assert await drive_on() == [1, 1]
    await tb.lb.write_reg('soft_drive1_enable', 0)
    assert await drive_on() == [1, 1], "enable applied before the fiducial"
    await tb.soft_trigger(20)
    assert await drive_on() == [1, 0]
    await tb.lb.write_reg('soft_drive1_enable', 1)
    await tb.soft_trigger(20)
    assert await drive_on() == [1, 1]


@cocotb.test(timeout_time=100, timeout_unit='us')
@cocotb.parametrize(loop=[0, 1])
async def test_phs_shift(dut, loop):
    """loopN_phs_shift is added to the phase setpoint while the pulse is on
    and pulse_clk (dsp clocks into the pulse, any pulse_res_shift) >=
    loopN_phs_shift_delay (plan L5: a delay past the pulse end shifts nothing). Checked on every dsp clock
    at loop_ctrl's phs_offset, against the other loop's different values."""
    tb = TB_llrf_shell(dut, f_config='LEMP', regmap_json_path='../../llrf_shell.json')
    await tb.lb.write_reg('wave_trig_sel', int(WaveTrigSel.Software))
    lc = tb.sig('loops').gen_loops[loop].loop_ctrl
    other = 1 - loop
    shift, mask = -12345, (1 << 18) - 1
    await tb.lb.write_reg(f'loop{other}_phs_shift', 777)
    await tb.lb.write_reg(f'loop{other}_phs_shift_delay', 3)
    await tb.lb.write_reg(f'loop{other}_pulse_start', 40)
    await tb.lb.write_reg(f'loop{other}_pulse_high_len', 7)
    for res, delay, high_len in ((0, 20, 60), (1, 21, 60), (3, 13, 60), (0, 100, 60), (0, 0, 30)):
        regs = {'phs_shift': shift & mask, 'phs_shift_delay': delay, 'pulse_start': 5,
                'pulse_high_len': high_len, 'pulse_res_shift': res}
        for k, v in regs.items():
            await tb.lb.write_reg(f'loop{loop}_{k}', v)
        await ClockCycles(dut.dsp_clk, 20)
        errors, shifted = [], 0
        await tb.lb.write_reg('soft_trigger', 1)
        for _ in range(5 + high_len + 40):
            await RisingEdge(dut.dsp_clk)
            await ReadOnly()
            dval, pclk = int(lc.pulse_dval.value), int(lc.pulse_clk.value)
            exp = shift if dval and pclk >= delay else 0
            got = lc.phs_offset.value.to_signed()
            shifted += got != 0
            if got != exp and len(errors) < 5:
                errors.append(f"dval {dval} pulse_clk {pclk}: phs_offset {got}, expected {exp}")
        assert not errors, f"res {res} delay {delay}: " + "; ".join(errors)
        n_exp = max(0, high_len - delay)  # clock resolution at any res_shift
        assert shifted == n_exp, f"res {res} delay {delay}: shifted {shifted} clocks, expected {n_exp}"


@cocotb.test(timeout_time=100, timeout_unit='us')
async def test_pmod_triggers(dut):
    """The four PMOD triggers restart on the fiducial (wave_trig while
    fiducial_sel is 0) and go high global_delay + trig_N_delay later for
    trig_N_width clocks; trig_enables gates each, and an interlock latch
    stops trigger 0 (modulator). A model of triggers.sv runs on the shell's
    fiducial, enables and global_delay and is checked on every clock."""
    tb = TB_llrf_shell(dut, f_config='LEMP', regmap_json_path='../../llrf_shell.json')
    await tb.lb.write_reg('fiducial_sel', 0)
    await tb.lb.write_reg('wave_trig_sel', int(WaveTrigSel.Software))
    cfg = [(10 + 7 * k, 3 + 2 * k) for k in range(4)]  # (delay, width), distinct per trigger
    for k, (delay, width) in enumerate(cfg):
        await tb.lb.write_reg(f'trig_{k}_delay', delay)
        await tb.lb.write_reg(f'trig_{k}_width', width)
    # a trigger with width 0 (boot value) stays high once fired (LEMP-branch
    # triggers.v), as earlier tests may have left them: disable to clear
    await tb.lb.write_reg('trig_enables', 0)
    await ClockCycles(dut.dsp_clk, 20)
    await tb.lb.write_reg('trig_enables', 0b1111)
    await ClockCycles(dut.dsp_clk, 20)
    trig = [tb.sig('gen_trig')[k].trig for k in range(4)]
    await ReadOnly()
    state = [[int(t.counter.value), int(t.trigger.value)] for t in trig]
    errors, highs = [], [0] * 4
    m32 = (1 << 32) - 1

    async def monitor():
        while True:
            await RisingEdge(dut.dsp_clk)
            fid, gd = int(tb.sig('fiducial_int').value), int(tb.sig('global_delay').value)
            en = int(tb.sig('trig_enable').value)
            for k, (delay, width) in enumerate(cfg):
                st, dt = state[k], (gd + delay) & m32
                if en >> k & 1:
                    if fid:
                        st[0] = 0
                    else:
                        c, st[0] = st[0], (st[0] + 1) & m32
                        st[1] = 1 if c == dt else 0 if c == (dt + width) & m32 else st[1]
                else:
                    st[1] = 0
            await ReadOnly()
            got = int(dut.pmod_trigs.value)
            for k in range(4):
                highs[k] += got >> k & 1
                if (got >> k & 1) != state[k][1] and len(errors) < 5:
                    errors.append(f"t={cocotb.utils.get_sim_time('ns')} trig {k}: {got >> k & 1}, expected {state[k][1]}")

    task = cocotb.start_soon(monitor())
    # once enabled, the counters run without a fiducial and fire once (the
    # fiducial resets the counter, not the output): settle, then count
    await tb.soft_trigger(80)
    highs[:] = [0] * 4
    for _ in range(3):
        await tb.soft_trigger(80)
    first = highs[:]
    dut.intlk_latch_in.value = 0b10
    await tb.soft_trigger(80)
    dut.intlk_latch_in.value = 0
    await tb.lb.write_reg('trig_enables', 0b0101)
    await tb.soft_trigger(80)
    task.cancel()
    assert not errors, "\n".join(errors)
    assert first == [3 * w for _, w in cfg], f"high clocks per trigger {first}"
    assert highs[0] == first[0] + cfg[0][1], "latched interlock did not stop trigger 0"
    assert highs[1] == first[1] + cfg[1][1] and highs[3] == first[3] + cfg[3][1], "enables"
    assert highs[2] == first[2] + 2 * cfg[2][1]


@cocotb.test(timeout_time=200, timeout_unit='us')
async def test_fiducial(dut):
    """fiducial_sel 1: after an EVR fiducial (event 1), fiducial_int_gen fires
    the fiducial with global_delay = trig_acc_delay if ACCL (151) came within
    the window and event_sel is 151, else trig_stb_delay if STBY (152) came;
    wave_trig (Fiducial selection) follows global_delay later. The four
    event codes appear on evr_events."""
    tb = TB_llrf_shell(dut, f_config='LEMP', regmap_json_path='../../llrf_shell.json')
    await tb.evr_idle()
    window = int(dut.FIDUCIAL_WINDOW.value)
    acc, stb = 300, 120
    for name, v in (('fiducial_sel', 1), ('trig_acc_delay', acc), ('trig_stb_delay', stb),
                    ('wave_trig_sel', int(WaveTrigSel.Fiducial))):
        await tb.lb.write_reg(name, v)
    fid, wave_trig = tb.sig('fiducial_int'), tb.sig('wave_trig')
    seen = set()

    async def watch_events():
        while True:
            await RisingEdge(dut.dsp_clk)
            ev = int(dut.evr_events.value)
            seen.update(k for k in range(4) if ev >> k & 1)
    ev_task = cocotb.start_soon(watch_events())

    async def message(event_sel, codes):
        """Times (dsp clocks from the message) of the fiducial and wave_trig."""
        await tb.lb.write_reg('event_sel', event_sel)
        t = {}

        async def watch():
            for n in itertools.count():
                await RisingEdge(dut.dsp_clk)
                await ReadOnly()
                for name, s in (('fid', fid), ('wave', wave_trig)):
                    if int(s.value) and name not in t:
                        t[name] = n
        task = cocotb.start_soon(watch())
        await tb.send_event(EV_FIDU)
        for c in codes:
            await ClockCycles(dut.gt_rxclk, 5)
            await tb.send_event(c)
        await ClockCycles(dut.dsp_clk, window + acc + 50)
        task.cancel()
        return t, int(tb.sig('global_delay').value)

    await tb.send_event(EV_TS)
    results = {}
    for event_sel, codes, delay in ((EV_ACCL, [EV_ACCL, EV_STBY], acc), (EV_ACCL, [EV_STBY], stb),
                                    (EV_STBY, [EV_ACCL, EV_STBY], stb), (EV_STBY, [EV_ACCL], None),
                                    (EV_ACCL, [], None), (0, [EV_ACCL, EV_STBY], None)):
        t, gd = await message(event_sel, codes)
        results[(event_sel, tuple(codes))] = t
        if delay is None:
            assert not t, f"event_sel {event_sel}, events {codes}: unexpected {t}"
            continue
        assert gd == delay, f"event_sel {event_sel}, events {codes}: global_delay {gd}"
        assert window <= t['fid'] <= window + 20, f"fiducial at {t['fid']}"
        results[delay] = t['wave'] - t['fid']
    ev_task.cancel()
    # wave_trig follows the fiducial by global_delay plus a fixed latency
    assert results[acc] - results[stb] == acc - stb, results
    assert 0 < results[stb] - stb < 6, results
    assert seen == {0, 1, 2, 3}, f"evr_events seen {seen}"
