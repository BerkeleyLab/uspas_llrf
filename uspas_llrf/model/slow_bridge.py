"""Decoder for the slow_bridge diagnostics block of cic_waves.

The slow block (llrf_dsp/slow_bridge_shell.v) snapshots auxiliary data
synchronously with a waveform buffer transfer and exposes it as 16-bit
words on the local bus at dsp_slow_data (0x10900, see static_regmap.json).
Word layout, starting at offset 0x11:

    0      cbuf_stat1   {record_type, buff_wrap, last_addr[13:0]}, circle_buf.v
    1      cbuf_stat2   last valid write address (CBUF_AW bits)
    2      cbuf_count   number of buffers acquired
    3      tag          dsp_tag at snapshot
    4      tag_old      dsp_tag at previous snapshot
    5..    adc_min[n_adc]   signed, ch0 first
    ..     adc_max[n_adc]   signed, ch0 first
    ..     evr_timestamp    4 words, MSB first: {seconds[31:0], ticks[31:0]}
    ..     cycle counter    8 words, low byte of each used, LSB first:
                            {fast[2:0], 5'b0}, count[7:0], ..., count[55:48]
                            (bedrock dsp/timestamp.v, 59-bit cycle counter)
"""
from dataclasses import dataclass, field
import numpy as np

SLOW_DATA_OFFSET = 0x11
SLOW_STATUS_WORDS = ['cbuf_stat1', 'cbuf_stat2', 'cbuf_count', 'tag', 'tag_old']
SLOW_EVR_TS_WORDS = 4
SLOW_CYCLE_WORDS = 8
CBUF_STAT1_RECORD_TYPE = 1 << 15   # 1: normal record, 0: stopped on fault
CBUF_STAT1_BUFF_WRAP = 1 << 14
CBUF_STAT1_ADDR_MASK = CBUF_STAT1_BUFF_WRAP - 1


def slow_data_n_words(n_adc=8):
    """Number of meaningful words after SLOW_DATA_OFFSET."""
    return len(SLOW_STATUS_WORDS) + 2 * n_adc + SLOW_EVR_TS_WORDS + SLOW_CYCLE_WORDS


@dataclass(eq=False)
class SlowData:
    """Decoded slow_bridge snapshot."""
    cbuf_stat1: int = 0
    cbuf_stat2: int = 0
    cbuf_count: int = 0
    tag: int = 0
    tag_old: int = 0
    adc_min: np.ndarray = field(default_factory=lambda: np.zeros(0, dtype=np.int32))
    adc_max: np.ndarray = field(default_factory=lambda: np.zeros(0, dtype=np.int32))
    evr_seconds: int = 0
    evr_ticks: int = 0
    cycles: int = 0
    raw: np.ndarray = field(default_factory=lambda: np.zeros(0, dtype=np.uint32))

    @property
    def fault(self):
        """True if the circle buffer was stopped by buf_stop (record_en low)."""
        return not (self.cbuf_stat1 & CBUF_STAT1_RECORD_TYPE)

    @property
    def buf_wrap(self):
        """True if the stopped buffer wrapped around before the stop."""
        return bool(self.cbuf_stat1 & CBUF_STAT1_BUFF_WRAP)

    @property
    def last_addr(self):
        """Last valid circle buffer write address of a fault record."""
        return self.cbuf_stat2

    @property
    def tag_changed(self):
        """True if dsp_tag changed between the two snapshots, i.e. settings
        may have changed while the waveform was being recorded."""
        return self.tag != self.tag_old

    @property
    def evr_timestamp(self):
        return (self.evr_seconds << 32) | self.evr_ticks

    def __eq__(self, other):
        if not isinstance(other, SlowData):
            return NotImplemented
        return np.array_equal(self.raw, other.raw)

    def __repr__(self):
        return (f"< SlowData: {'FAULT' if self.fault else 'normal'}"
                f" count={self.cbuf_count} tag={self.tag:#04x}"
                f" tag_old={self.tag_old:#04x} last_addr={self.last_addr:#x}"
                f" wrap={self.buf_wrap} evr={self.evr_seconds}s+{self.evr_ticks}"
                f" cycles={self.cycles} >")


def decode_slow_data(words, n_adc=8, offset=SLOW_DATA_OFFSET):
    """Decode raw dsp_slow_data words into a SlowData.

    Args:
        words: iterable of 16-bit words as read from dsp_slow_data, either the
            full 256-word block (then `offset` is skipped) or already starting
            at the status words (offset=0).
        n_adc: number of ADC channels in min/max.
        offset: index of cbuf_stat1 in `words`.
    """
    raw = np.asarray(list(words), dtype=np.uint32) & 0xFFFF
    n = slow_data_n_words(n_adc)
    assert len(raw) >= offset + n, \
        f'need {offset + n} slow words, got {len(raw)}'
    w = raw[offset:offset + n]
    pos = 0
    status = {k: int(v) for k, v in zip(SLOW_STATUS_WORDS, w[pos:pos + len(SLOW_STATUS_WORDS)])}
    pos += len(SLOW_STATUS_WORDS)
    adc_min = w[pos:pos + n_adc].astype(np.int16).astype(np.int32)
    pos += n_adc
    adc_max = w[pos:pos + n_adc].astype(np.int16).astype(np.int32)
    pos += n_adc
    ts = 0
    for v in w[pos:pos + SLOW_EVR_TS_WORDS]:
        ts = (ts << 16) | int(v)
    pos += SLOW_EVR_TS_WORDS
    cyc = [int(v) & 0xFF for v in w[pos:pos + SLOW_CYCLE_WORDS]]
    fast = cyc[0] >> 5
    count = 0
    for b in reversed(cyc[1:]):
        count = (count << 8) | b
    return SlowData(
        **status, adc_min=adc_min, adc_max=adc_max,
        evr_seconds=ts >> 32, evr_ticks=ts & 0xFFFFFFFF,
        cycles=(count << 3) | fast, raw=raw)
