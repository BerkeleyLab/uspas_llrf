import numpy as np
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, First
from uspas_llrf import dsp_config, wrap_phase, CICWaveRecorder, LocalBusMaster
from uspas_llrf.model.slow_bridge import (
    decode_slow_data, slow_data_n_words, SLOW_DATA_OFFSET)


class TB:
    DSP_TAG = 0x5A
    EVR_TS = (0x1234_5678 << 32) | 0x9ABC_DEF0

    def __init__(self, dut, conf='USPAS', wave_samp_per=2, chan_keep=0b11,
                 post_delay=0):
        self.dut = dut
        self.config = config = dsp_config[conf]
        self.wave_samp_per = wave_samp_per
        self.chan_keep = chan_keep
        self.post_delay = post_delay

        self.cic_inlk = CICWaveRecorder(
            num=config['NUM_DDS'], den=config['DEN_DDS'],
            cic_base_period=config['CIC_BASE_PERIOD'],
            shift_base=config['INLK_SHIFT_BASE'])
        self.cic_mon = CICWaveRecorder(
            num=config['NUM_DDS'], den=config['DEN_DDS'],
            cic_base_period=config['CIC_BASE_PERIOD'],
            shift_base=config['CIC_SHIFT_BASE'],
            wave_samp_per=self.wave_samp_per)
        self.lb = LocalBusMaster(dut, dut.lb_clk)
        self.dsp_clk = dut.dsp_clk
        self.lb_clk = dut.lb_clk

        attrs = ['N_CH', 'N_ADC', 'CBUF_AW', 'CBUF_DW',
                 'P_ADDR_CBUF_DATA_BASE', 'P_ADDR_CBUF_READY', 'P_ADDR_CBUF_TRANSFERED',
                 'P_ADDR_CBUF_FLIP', 'P_ADDR_SLOW_READY', 'P_ADDR_SLOW_DATA_BASE']
        for attr in attrs:
            setattr(self, attr, getattr(dut, attr).value.to_unsigned())

        cocotb.start_soon(Clock(self.dsp_clk, 8, unit='ns').start())
        cocotb.start_soon(Clock(self.lb_clk, 8, unit='ns').start())

    async def reset(self):
        dut = self.dut
        dut.dsp_reset.value = 1
        dut.iq_dval.value = 0
        dut.ext_trig.value = 0
        dut.record_en.value = 1
        dut.cbuf_post_delay.value = 0  # register default after power-up
        dut.cbuf_buf_flip.value = 0
        dut.lb_read.value = 0
        dut.lb_addr.value = 0

        await ClockCycles(self.dsp_clk, 10)
        dut.dsp_reset.value = 0
        await RisingEdge(self.dsp_clk)

    async def configure(self):
        dut = self.dut
        dut.cic_wave_samp_per.value = self.wave_samp_per
        dut.cic_base_period.value = self.config['CIC_BASE_PERIOD']
        dut.cic_chan_keep.value = self.chan_keep
        dut.cic_wave_shift.value = self.cic_mon.wave_shift
        dut.inlk_wave_shift.value = self.cic_inlk.wave_shift
        dut.cbuf_post_delay.value = self.post_delay
        dut.dsp_tag.value = self.DSP_TAG
        dut.evr_timestamp.value = self.EVR_TS
        self.cic_chans = [
            int(b) for b in f'{self.chan_keep:010b}'][::-1]
        self.cic_n_chan = self.cic_chans.count(1)
        for ch in range(self.N_ADC):
            dut.slow_bridge_data_in[ch].value = 0

    async def pulse_ext_trig(self):
        dut = self.dut
        dut.ext_trig.value = 1
        await RisingEdge(self.dsp_clk)
        dut.ext_trig.value = 0

    async def set_wave_trig_sel(self, trig_sel='WAVE_TRIG_ALWAYS'):
        dut = self.dut
        v = getattr(dut, trig_sel).value.to_unsigned()
        dut.wave_trig_sel.value = v
        await RisingEdge(self.dsp_clk)

    def set_iq(self, i=100, q=200):
        dut = self.dut
        for ch in range(self.N_CH):
            dut.iq_data[2 * ch].value = int(i)
            dut.iq_data[2 * ch + 1].value = int(q)

    async def stream_iq_data(self, sample_count=512, i=100, q=200):
        dut = self.dut

        dut.iq_dval.value = 1
        for sample in range(sample_count):
            self.set_iq(i, q)
            for ch in range(self.N_ADC):
                dut.slow_bridge_data_in[ch].value = (sample + ch) & 0xFFFF
            await RisingEdge(self.dsp_clk)

    @staticmethod
    def to_signed(value, width):
        """Sign-extend a zero-extended bus word of the given width."""
        value &= (1 << width) - 1
        return value - (1 << width) if value & (1 << (width - 1)) else value

    async def read_cic_waveform(self, chan=0):
        await self.lb.write(self.P_ADDR_CBUF_FLIP, 1)
        await RisingEdge(self.dut.cbuf_transferred)
        return await self.read_cbuf(chan)

    @property
    def cbuf_span_cycles(self):
        """dsp_clk cycles to fill the circle buffer once."""
        n_samples = (1 << self.CBUF_AW) // self.cic_n_chan // 2
        return n_samples * self.config['CIC_BASE_PERIOD'] * self.wave_samp_per

    async def read_cbuf(self, chan=0):
        """Read one channel of the buffer already handed over."""
        dut = self.dut
        assert (await self.lb.read(self.P_ADDR_CBUF_READY)).value.to_unsigned()
        dut.lb_read.value = 1
        wfm = []
        n_samples = (1 << self.CBUF_AW) // self.cic_n_chan // 2
        for idx in range(n_samples):
            offset = self.cic_n_chan * idx * 2 + self.P_ADDR_CBUF_DATA_BASE
            rdata = await self.lb.read(offset + chan * 2)
            i = self.to_signed(rdata.value.to_unsigned(), self.CBUF_DW)
            rdata = await self.lb.read(offset + chan * 2 + 1)
            q = self.to_signed(rdata.value.to_unsigned(), self.CBUF_DW)
            wfm.append(i + 1j * q)

        dut.lb_addr.value = 0
        dut.lb_read.value = 0
        return np.array(wfm, dtype=np.complex64)

    async def read_slow_data(self):
        """Read the slow_bridge block through the local bus and decode it
        with uspas_llrf.model.slow_bridge, the same decoder LLRFApp uses.
        Mirrors the dsp_slow_data window (0x109??) in llrf_shell.v.
        """
        dut = self.dut
        assert (await self.lb.read(self.P_ADDR_SLOW_READY)).value.to_unsigned(), \
            'slow_ready not set after waveform transfer'
        n_words = SLOW_DATA_OFFSET + slow_data_n_words(self.N_ADC)
        dut.lb_read.value = 1
        words = []
        for idx in range(n_words):
            addr = self.P_ADDR_SLOW_DATA_BASE + idx
            words.append((await self.lb.read(addr)).value.to_unsigned())
        dut.lb_addr.value = 0
        dut.lb_read.value = 0

        slow = decode_slow_data(words, n_adc=self.N_ADC)
        cocotb.log.info(f'{slow}')
        return slow

    def check_sig(self, sig_meas, sig_name='signal', amp_exp=0.0, phs_exp=0.0):
        """Check the measured signal against expected amplitude and phase."""
        amp_meas = np.abs(sig_meas)
        phs_meas = np.angle(sig_meas, deg=True)
        cocotb.log.warning(
            f"expected {sig_name:12s} mag: {amp_exp:8.2f} cnt,  "
            f"phs: {phs_exp:6.3f} deg")
        cocotb.log.warning(
            f"measured {sig_name:12s} mag: {amp_meas:8.2f} cnt,  "
            f"phs: {phs_meas:6.3f} deg")
        amp_err = abs(amp_meas - amp_exp) / amp_exp
        assert amp_err < 0.001, "amplitude out-of-bound of 0.1%"
        phs_err = abs(wrap_phase(phs_meas - phs_exp))
        assert phs_err < 0.1, "phase out-of-bound of 0.1 deg"


@cocotb.test(timeout_time=200, timeout_unit='us')
@cocotb.parametrize(
    trig_sel=['WAVE_TRIG_ALWAYS', 'WAVE_TRIG_INT']
)
async def test_cic_waves_capture(dut, trig_sel='WAVE_TRIG_ALWAYS'):
    tb = TB(dut)
    await tb.reset()
    await tb.configure()
    await tb.set_wave_trig_sel(trig_sel)
    await tb.pulse_ext_trig()
    test_sig = 100 + 1j * 200
    await tb.stream_iq_data(i=test_sig.real, q=test_sig.imag)

    cic_meas = await tb.read_cic_waveform()
    cic_meas = cic_meas[2:]  # XXX discard first 2 samples due to transient
    tb.check_sig(
        cic_meas.mean() / tb.cic_mon.gain, sig_name='chan0',
        amp_exp=np.abs(test_sig), phs_exp=np.angle(test_sig, deg=True))


@cocotb.test(timeout_time=200, timeout_unit='us')
async def test_cic_waves_record_en(dut):
    """Toggle record_en and check buffer freeze/resume through slow readout.

    record_en=0 lets the post-delay counter run; after cbuf_post_delay
    buffer syncs the circular buffer stops writing until the host flips
    it. The frozen buffer keeps the old signal, buf_stat1 flags the capture
    as a fault record, and recording resumes once record_en is reasserted
    and the buffer has been read out.
    """
    tb = TB(dut, post_delay=1)
    await tb.reset()
    await tb.configure()
    await tb.set_wave_trig_sel('WAVE_TRIG_ALWAYS')
    sig_a = 100 + 1j * 200
    sig_c = -300 + 1j * 50
    await tb.stream_iq_data(i=sig_a.real, q=sig_a.imag)

    # Free running with record_en=1: readout and slow block are sane.
    cic_meas = await tb.read_cic_waveform()
    tb.check_sig(
        cic_meas[2:].mean() / tb.cic_mon.gain, sig_name='run_a',
        amp_exp=np.abs(sig_a), phs_exp=np.angle(sig_a, deg=True))
    slow_run = await tb.read_slow_data()
    assert not slow_run.fault, 'free-running buffer flagged as fault record'
    assert slow_run.tag == tb.DSP_TAG
    assert slow_run.tag_old == tb.DSP_TAG
    assert not slow_run.tag_changed
    assert slow_run.evr_timestamp == tb.EVR_TS, \
        f'evr_timestamp {slow_run.evr_timestamp:#018x} != {tb.EVR_TS:#018x}'
    assert np.all(slow_run.adc_max >= slow_run.adc_min)
    # without a flip the slow block holds the previous snapshot
    slow_run2 = await tb.read_slow_data()
    assert slow_run2 == slow_run, 'slow data moved without a flip'

    # Drop record_en: freeze after post_delay syncs, then change the input.
    dut.record_en.value = 0
    for _ in range(tb.post_delay + 2):
        await RisingEdge(dut.cbuf_sync)
    await ClockCycles(tb.dsp_clk, 50)
    tb.set_iq(sig_c.real, sig_c.imag)
    await ClockCycles(tb.dsp_clk, 1500)

    cic_frozen = await tb.read_cic_waveform()
    tb.check_sig(
        cic_frozen.mean() / tb.cic_mon.gain, sig_name='frozen_a',
        amp_exp=np.abs(sig_a), phs_exp=np.angle(sig_a, deg=True))
    assert np.all(np.abs(cic_frozen / tb.cic_mon.gain - sig_c) > 100), \
        'frozen buffer contains samples recorded after record_en dropped'
    slow_frozen = await tb.read_slow_data()
    assert slow_frozen.fault, 'frozen buffer not flagged as fault record'
    assert slow_frozen.cbuf_count > slow_run.cbuf_count
    assert slow_frozen.cycles > slow_run.cycles, 'cycle counter not advancing'

    # Re-enable recording: buffer follows the new input again.
    dut.record_en.value = 1
    await tb.read_cic_waveform()  # discard, recording resumes on this flip
    cic_resumed = await tb.read_cic_waveform()
    tb.check_sig(
        cic_resumed[2:].mean() / tb.cic_mon.gain, sig_name='resumed_c',
        amp_exp=np.abs(sig_c), phs_exp=np.angle(sig_c, deg=True))
    slow_resumed = await tb.read_slow_data()
    assert not slow_resumed.fault, 'resumed buffer flagged as fault record'
    assert slow_resumed.cbuf_count > slow_frozen.cbuf_count


@cocotb.test(timeout_time=400, timeout_unit='us')
async def test_cic_waves_post_delay_write(dut):
    """cbuf_post_delay writes must not stop the buffer while record_en=1.

    cbuf_delay_stop compares delay_cnt (held at 0 while record_en=1)
    against cbuf_post_delay, so a write of 0 used to raise it and fire a
    spurious buf_stop, flagging the next buffer as a fault record.
    The power-up default of 0 had the same edge on the first cycle.
    post_delay=0 keeps the freeze disabled when record_en drops.
    """
    tb = TB(dut, post_delay=0)
    await tb.reset()
    await tb.configure()
    await tb.set_wave_trig_sel('WAVE_TRIG_ALWAYS')
    await tb.stream_iq_data()

    async def check_no_fault(label, n_bufs=2):
        for _ in range(n_bufs):
            await tb.read_cic_waveform()
            slow = await tb.read_slow_data()
            assert not slow.fault, f'{label}: buffer flagged as fault record'

    await check_no_fault('power-up with post_delay=0')
    for a, b in [(3, 0), (0, 1), (1, 3), (3, 1), (1, 0)]:
        dut.cbuf_post_delay.value = a
        await check_no_fault(f'post_delay={a}', n_bufs=1)
        dut.cbuf_post_delay.value = b
        for _ in range(3):
            await RisingEdge(dut.cbuf_sync)
        await check_no_fault(f'post_delay write {a}->{b}')

    # post_delay=0 disables the freeze
    dut.record_en.value = 0
    for _ in range(4):
        await RisingEdge(dut.cbuf_sync)
    await check_no_fault('record_en=0 with post_delay=0')
    dut.record_en.value = 1


@cocotb.test(timeout_time=200, timeout_unit='us')
async def test_cic_waves_ext_trig(dut):
    """External trigger mode records one buffer per trigger.

    stream_valid gates the circle buffer writes (buf_write): after a buffer
    is full, writing stops until the next wave_trig. circle_buf hands over
    a buffer only when it completes with a flip pending, so the reader arms
    with a flip before the trigger. Without a trigger nothing is handed
    over and the last waveform stays frozen.
    """
    tb = TB(dut)
    await tb.reset()
    await tb.configure()
    await tb.set_wave_trig_sel('WAVE_TRIG_EXT')
    sig_a = 100 + 1j * 200
    sig_b = -300 + 1j * 50
    await tb.stream_iq_data(i=sig_a.real, q=sig_a.imag)

    async def arm_and_wait(trigger):
        await tb.lb.write(tb.P_ADDR_CBUF_FLIP, 1)
        if trigger:
            await tb.pulse_ext_trig()
        n_cycles = 4 * tb.cbuf_span_cycles
        first = await First(RisingEdge(dut.cbuf_transferred),
                            ClockCycles(tb.dsp_clk, n_cycles))
        return not isinstance(first, ClockCycles)

    # buffer recorded after a trigger is handed over
    assert await arm_and_wait(trigger=True), 'no buffer after trigger'
    cic_meas = await tb.read_cbuf()
    tb.check_sig(
        cic_meas[2:].mean() / tb.cic_mon.gain, sig_name='trig_a',
        amp_exp=np.abs(sig_a), phs_exp=np.angle(sig_a, deg=True))

    # no trigger: nothing is handed over
    tb.set_iq(sig_b.real, sig_b.imag)
    assert not await arm_and_wait(trigger=False), \
        'buffer handed over without trigger'

    # the next trigger records a fresh buffer with the new signal
    await tb.pulse_ext_trig()
    await RisingEdge(dut.cbuf_transferred)
    cic_meas = await tb.read_cbuf()
    tb.check_sig(
        cic_meas[2:].mean() / tb.cic_mon.gain, sig_name='trig_b',
        amp_exp=np.abs(sig_b), phs_exp=np.angle(sig_b, deg=True))


@cocotb.test(timeout_time=200, timeout_unit='us')
async def test_cic_waves_inlk_continuous(dut):
    """The interlock stream must not see the circle buffer write gate.

    buf_write (stream_valid) only gates the strobes into circle_buf_serial;
    the interlock ccfilt taps di_sr_out before it. Log every inlk beat while
    stream_valid toggles through a triggered record, a stop, Always mode and
    another trigger, and check the frames stay regular and unchanged.
    """
    tb = TB(dut)
    await tb.reset()
    await tb.configure()
    await tb.set_wave_trig_sel('WAVE_TRIG_EXT')
    await tb.stream_iq_data(i=100, q=200)
    stream_valid = dut.dut.stream_valid
    span = tb.cbuf_span_cycles

    beats = []
    gate = []

    async def monitor():
        cycle = 0
        while True:
            await RisingEdge(tb.dsp_clk)
            cycle += 1
            gate.append(int(stream_valid.value))
            if dut.inlk_dval.value:
                beats.append((cycle, int(dut.inlk_last.value),
                              dut.inlk_data.value.to_signed()))

    mon = cocotb.start_soon(monitor())
    await tb.pulse_ext_trig()                     # record one buffer, stop
    await ClockCycles(tb.dsp_clk, 3 * span)
    await tb.set_wave_trig_sel('WAVE_TRIG_ALWAYS')  # free run
    await ClockCycles(tb.dsp_clk, 2 * span)
    await tb.set_wave_trig_sel('WAVE_TRIG_EXT')   # stops at next cbuf_sync
    await ClockCycles(tb.dsp_clk, 2 * span)
    await tb.pulse_ext_trig()
    await ClockCycles(tb.dsp_clk, 3 * span)
    mon.cancel()

    edges = sum(a != b for a, b in zip(gate, gate[1:]))
    assert 0 in gate and 1 in gate and edges >= 4, \
        f'stream_valid did not toggle enough ({edges} edges)'

    # split beats into frames ending with inlk_last
    frames, cur = [], []
    for cycle, last, data in beats:
        cur.append((cycle, data))
        if last:
            frames.append(cur)
            cur = []
    frames = frames[1:]  # monitor may start mid-frame
    n_beats = 2 * tb.N_CH
    short = [i for i, f in enumerate(frames) if len(f) != n_beats]
    assert not short, f'inlk frames {short} of {len(frames)} not {n_beats} beats'
    starts = [f[0][0] for f in frames]
    periods = {b - a for a, b in zip(starts, starts[1:])}
    assert periods == {tb.config['CIC_BASE_PERIOD']}, \
        f'inlk frame periods {periods}'
    # constant input: steady-state frames carry identical data
    datas = [tuple(d for _, d in f) for f in frames[5:]]
    assert len(set(datas)) == 1, \
        f'inlk data changed across {len(set(datas))} distinct frames'
    cocotb.log.info(f'{len(frames)} inlk frames, period {periods}, '
                    f'{edges} stream_valid edges, data {datas[0][:4]}')
