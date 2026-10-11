"""Bit-accurate, cycle-level models of llrf_dsp/pulse_gen.v and the pulse
modulation in llrf_dsp/loop_ctrl.v, used as cocotb scoreboards.

Each step() is one dsp_clk rising edge: next values are computed from the
current register state and the inputs, then committed.
"""


def wrap_signed(value, width):
    """value modulo 2**width, as a two's-complement signed int."""
    value &= (1 << width) - 1
    return value - (1 << width) if value >> (width - 1) else value


class PulseGen:
    """pulse_gen.v: pulse_dval for count in [start, start+high_len),
    pulse_idx = (count - start) >> res registered with pulse_dval."""

    def __init__(self, aw=32):
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

    def step(self, trigger, start, high_len, stb=1, res=0):
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


class PulseModulator:
    """loop_ctrl.v pulse counter, modulation tables and modulated setpoints.

    The setpoints follow pulse_idx/pulse_dval by 2 clocks: the table read
    (dpram latches the index) and the output register.
    """

    def __init__(self, dwbb=18, pulse_aw=32, mod_aw=14):
        self.dwbb = dwbb
        self.mod_aw = mod_aw
        self.mod_size = 1 << mod_aw
        self.sat_max = (1 << (dwbb - 1)) - 1
        self.sat_min = -(1 << (dwbb - 1))
        self.pulse = PulseGen(pulse_aw)
        self.amp_mod_table = [0] * self.mod_size
        self.phs_mod_table = [0] * self.mod_size
        # configuration (loop_ctrl inputs)
        self.pulse_start = 0
        self.pulse_high_len = 0
        self.res_shift = 0
        self.mod_len = 0
        self.amp_mod_enable = 0
        self.phs_mod_enable = 0
        self.amp_setpoint = 0
        self.max_amp_setpoint = 0
        self.phs_setpoint = 0
        self.phs_offset = 0
        self.amp_loop_enable = 0
        # registers
        self.mod_addr = 0
        self.amp_mod_gate = 0
        self.phs_mod_gate = 0
        self.amp_sp = 0
        self.phs_sp = 0

    def sat(self, x):
        return max(self.sat_min, min(self.sat_max, x))

    def drive_on(self, drive_permit, pulse_mode):
        return int(drive_permit and (self.pulse.dval if pulse_mode else 1))

    def step(self, trigger=0):
        p = self.pulse
        mod_len = min(self.mod_len, self.mod_size)
        in_mod = p.dval and p.idx < mod_len
        amp_mod = wrap_signed(self.amp_mod_table[self.mod_addr], self.dwbb)
        phs_mod = wrap_signed(self.phs_mod_table[self.mod_addr], self.dwbb)
        amp = self.sat(self.amp_setpoint + (amp_mod if self.amp_mod_gate else 0))
        if not self.amp_loop_enable and amp > self.max_amp_setpoint:
            amp = self.max_amp_setpoint
        phs = wrap_signed(self.phs_setpoint + (phs_mod if self.phs_mod_gate else 0)
                          + self.phs_offset, self.dwbb)
        # commit
        self.amp_sp, self.phs_sp = amp, phs
        self.amp_mod_gate = int(in_mod and self.amp_mod_enable)
        self.phs_mod_gate = int(in_mod and self.phs_mod_enable)
        self.mod_addr = p.idx & (self.mod_size - 1)
        p.step(trigger, self.pulse_start, self.pulse_high_len, 1, self.res_shift)
