"""llrf_shell register map: declaration, address allocation and generated
outputs (plan §2.4). Replaces newad for llrf_shell.

The base map is base_regs() (rw registers), base_status() (status words),
base_blocks() (readback windows) and base_aliases(). A design extends the
registers in designs/<d>/design.py, which defines design(rm) returning the
register list; rm is this module. It is the single source of register facts:
besides the generated outputs below, the model's boot-time registers
(init_registers(), LLRFShell) and the register encodings (WaveTrigSel,
DacDriveSel, InlkFaultMode) come from here.

Outputs, written by the command line below:
- llrf_shell_regmap_pkg.sv: cfg_<domain>_t and status_<domain>_t structs,
  ADDR_* constants, MAP_SIG_BUF_AW and MAP_MOD_AW;
- llrf_shell_regs.sv: register storage and decode, the readback mirror, the
  status banks, the write strobes of writable windows (modulation tables)
  and the readback mux over every window;
- llrf_shell.json: the whole register map (leep schema).

rw register addresses are allocated as newad did (newad.py -l -m -w 17
-b 0x11000): largest tables first, then by name.

This module uses the standard library only: the design build runs it as a
script, without importing the uspas_llrf package.
"""
import argparse
import dataclasses
import json
import os
from dataclasses import dataclass
from enum import IntEnum
from pathlib import Path
from typing import Optional

# register domain -> localbus copy in llrf_shell (data_xdomain from lb_clk)
DOMAINS = {'lb': 'lb', 'dsp': 'lb1', 'dac': 'lb2', 'evr': 'lb3'}
LB_HI = 17           # localbus address MSB (newad -w)
RW_BASE = 0x11000    # rw register window, mirrored for readback
MIRROR_MAX_AW = 5    # registers and tables up to 2^5 entries are mirrored
N_DRIVE = 2
N_ADC = 8
SIG_BUF_AW = 11      # signal buffer depth 2^SIG_BUF_AW (D1); designs may override
SIG_BUF_BASE = 0x12000
MOD_AW = 14          # modulation table depth 2^MOD_AW (loop_ctrl)
MOD_BASE = 0x20000   # amplitude and phase tables of each loop (§1.1)
CBUF_BASE = 0x30000
DESIGNS_DIR = Path(__file__).resolve().parents[1] / 'designs'

# Renames and additions against the step-1 baseline JSON; test_regmap_compat
# allows exactly these differences (plan §2.4.1).
RENAMES = {
    'arc_test_arc_dev': ['arc_test_mask', 'arc_test_stb'],                # D18, step 3
    'pulse_modes': ['drv0_pulse_mode', 'drv1_pulse_mode'],                # D11, step 7c
    'soft_drive_enable': ['soft_drive0_enable', 'soft_drive1_enable'],    # D11, step 7c
    'lut0_len': ['loop0_mod_len'],                                        # pip-ii, step 7d
    'lut1_len': ['loop1_mod_len'],
    'pulse_res_shift': ['loop0_pulse_res_shift', 'loop1_pulse_res_shift'],
    'pulse_modulation_enable': ['loop0_amp_mod_enable', 'loop1_amp_mod_enable'],
    'pulse0_lut': ['loop0_amp_mod'],
    'pulse1_lut': ['loop1_amp_mod'],
}
ADDITIONS = ['arc_testing',                                               # D18, step 3
             *[f'loop{n}_{x}' for n in range(2) for x in ('phs_mod', 'phs_mod_enable')],  # step 7d
             'buf_delay']                                                 # LEMP, step 8
# registers whose data_width changed on purpose: name -> new width
WIDTH_CHANGES = {f'loop{n}_pulse_{f}': 32 for n in range(2) for f in ('start', 'high_len')}  # step 7d
REMOVALS = ['iq_buf',                     # 2K designs: only LEMP keeps it (D1), step 7b
            'dac0_raw_out', 'dac1_raw_out']  # awa: zero-valued buffers retired (§1.3), step 7b


class WaveTrigSel(IntEnum):
    Internal = 0
    External = 1
    Software = 2
    EVR = 3
    Always = 4
    Mixed = 5


class DacDriveSel(IntEnum):
    I0Q0 = 0
    I1Q1 = 1
    I0I1 = 2
    Q0Q1 = 3


class InlkFaultMode(IntEnum):
    LoLo = 0b00  # V < lower_thresh and V < upper_thresh
    LoHi = 0b01  # lower_thresh <= V < upper_thresh
    HiLo = 0b10  # upper_thresh <= V < lower_thresh (shouldn't happen)
    HiHi = 0b11  # V >= lower_thresh and V >= upper_thresh


@dataclass
class Reg:
    """One rw register (aw == 0) or register table (aw > 0, a dpram).

    kind: 'rw' holds the written value; 'strobe' is high for one cycle
    after the write (newad single-cycle).
    inst: block instance whose port the register drives; the port name is
    the register name without the '<inst>_' prefix.
    enum: IntEnum of the register (or table entry) encoding.
    init: value the firmware writes at boot (init_llrf.c); None: not written.
    The model overrides it with values derived from the DSP configuration.
    """
    name: str
    width: int = 1
    domain: str = 'dsp'
    kind: str = 'rw'
    signed: bool = False
    aw: int = 0
    inst: Optional[str] = None
    enum: Optional[type[IntEnum]] = None
    init: Optional[int] = None
    description: str = ''

    def __post_init__(self):
        assert self.domain in DOMAINS, (self.name, self.domain)
        assert self.kind in ('rw', 'strobe'), (self.name, self.kind)
        assert not (self.aw and self.kind != 'rw'), self.name
        assert not self.inst or self.name.startswith(self.inst + '_'), self.name
        assert not (self.init is not None and (self.aw or self.kind != 'rw')), self.name
        if self.enum is not None:
            for e in self.enum:
                self.value(e)
        if self.init is not None:
            self.init = self.value(self.init)

    @property
    def port(self):
        assert self.inst is not None, self.name
        return self.name[len(self.inst) + 1:]

    def value(self, v):
        """v as the register holds it: an int (or enum member) in range."""
        v = self.enum(v) if self.enum else int(v)
        lo, hi = (-(1 << (self.width - 1)), 1 << (self.width - 1)) if self.signed else (0, 1 << self.width)
        if not lo <= v < hi:
            raise ValueError(f"{self.name}: {v} does not fit {'signed' if self.signed else 'unsigned'}"
                             f" {self.width} bits")
        return v


def loop_regs(n):
    w = 18
    return [Reg(f'loop{n}_amp_setpoint', w, signed=True, init=0),
            Reg(f'loop{n}_max_amp_setpoint', w, signed=True, init=0),
            Reg(f'loop{n}_phs_setpoint', w, signed=True, init=0),
            Reg(f'loop{n}_Kp_amp', w, signed=True, init=0),
            Reg(f'loop{n}_Kp_phs', w, signed=True, init=0),
            Reg(f'loop{n}_Ki_amp', w, signed=True, init=0),
            Reg(f'loop{n}_Ki_phs', w, signed=True, init=0),
            Reg(f'loop{n}_amp_enable', init=0),
            Reg(f'loop{n}_phs_enable', init=0),
            Reg(f'loop{n}_amp_reset', init=0),
            Reg(f'loop{n}_phs_reset', init=0)]


def base_regs():
    """Registers shared by all designs, in the order of the decode."""
    regs = [
        Reg('circle_buf_flip', domain='lb', kind='strobe'),
        Reg('sig_buf_flip', domain='lb', kind='strobe'),
        Reg('dsp_tag', 8),
        # buffer syncs from a drive permit drop to the fault record freeze;
        # 0 (power-up value) disables the freeze, see cic_waves.v
        Reg('cbuf_post_delay', 16, init=1),
        Reg('wave_samp_per', 7, init=1),
        Reg('chan_keep', 10, init=0),
        Reg('cic_base_period', 7, init=14),
        Reg('cic_wave_shift', 4, init=0),
        Reg('inlk_wave_shift', 4, init=0),
        Reg('inlk_permit_mask', 10, init=0),
        Reg('arc_permit_mask', 8, init=0),
        Reg('rx_dds_phase_step', 32, init=0),
        Reg('rx_dds_phase_shift', 19, signed=True, init=0),
        Reg('rx_dds_modulo', 12, init=0),
        Reg('rx_dds_amplitude', 18, init=0),
        Reg('rx_phase_offset', 19, signed=True, init=0),
        Reg('tx_phase_offset', 19, signed=True, init=0),
        Reg('prl_adc_chan', 3, init=0),
        *[Reg(f'loop{n}_adc_chan', 3, init=0) for n in range(N_DRIVE)],
        *[r for n in range(N_DRIVE) for r in loop_regs(n)],
        Reg('dsp_reset', kind='strobe'),
        *[Reg(f'loop{n}_pulse_{f}', 32, init=v) for n in range(N_DRIVE)
          for f, v in (('start', 0), ('high_len', 10))],
        # pulse modulation (loop_ctrl); all 0 keeps CW behavior
        *[r for n in range(N_DRIVE) for r in (
            Reg(f'loop{n}_pulse_res_shift', 4, init=0),
            Reg(f'loop{n}_mod_len', MOD_AW + 1, init=0, description='modulation table entries used'),
            Reg(f'loop{n}_amp_mod_enable', init=0),
            Reg(f'loop{n}_phs_mod_enable', init=0))],
        *[Reg(f'drv{n}_pulse_mode', init=0) for n in range(N_DRIVE)],
        *[Reg(f'soft_drive{n}_enable', init=1) for n in range(N_DRIVE)],
        Reg('ntw_amp_enable'),
        Reg('ntw_phs_enable'),
        Reg('system_bist_pass'),
        Reg('wave_trig_sel', 3, enum=WaveTrigSel, init=WaveTrigSel.Always),
        Reg('trigger_delay', 24, init=0),
        Reg('buf_delay', 32, init=0, description='dsp clocks from wave_trig to the signal and circle buffer captures'),
        Reg('int_trigger_period', 32, init=5750000),
        Reg('soft_trigger', kind='strobe'),
        Reg('slow_snap_cic', init=0),
        Reg('ext_permit_bypass'),
        Reg('dac_drive_sel', 2, domain='dac', enum=DacDriveSel, init=DacDriveSel.I0Q0),
        Reg('tx_dds_phase_step', 32, domain='dac', init=0),
        Reg('tx_dds_phase_shift', 19, domain='dac', signed=True, init=0),
        Reg('tx_dds_modulo', 12, domain='dac', init=0),
        Reg('tx_dds_amplitude', 18, domain='dac', init=0),
        Reg('duc_spectral_flip', domain='dac', init=0),
        Reg('tx_afe_spectral_flip', domain='dac', init=0),
        Reg('evcode', 8, domain='evr', init=0),
        Reg('evr_oc_delay', 7, domain='evr'),
        # monitor_inlk inlk
        Reg('inlk_amp_lo', 16, aw=4, inst='inlk'),
        Reg('inlk_amp_hi', 16, aw=4, inst='inlk'),
        Reg('inlk_reset_inlk', kind='strobe', inst='inlk'),
        Reg('inlk_inlk_mode', 2, aw=4, inst='inlk', enum=InlkFaultMode),
        # arc_inlk arc
        Reg('arc_reset_latch', kind='strobe', inst='arc'),
        Reg('arc_reset_arc_dev', kind='strobe', inst='arc'),
        Reg('arc_test_mask', 8, inst='arc'),
        Reg('arc_test_stb', kind='strobe', inst='arc'),
        # ntw_analyzer ntw
        Reg('ntw_lo_amp', 18, inst='ntw'),
        Reg('ntw_modulo', 12, inst='ntw'),
        Reg('ntw_phase_step_h', 32, inst='ntw'),
        Reg('ntw_phase_step_l', 12, inst='ntw'),
    ]
    return regs


@dataclass
class Status:
    """Read-only status word at addr, in a 16-word bank. 'lb' banks hold
    lb_clk values and are registered on lb_read; the 'dsp' bank holds dsp_clk
    values, read through jit_rad_gateway (prefill, then read)."""
    name: str
    width: int
    addr: int
    domain: str = 'lb'
    signed: bool = False
    description: str = ''

    def __post_init__(self):
        assert self.domain in ('lb', 'dsp'), (self.name, self.domain)
        assert 0 < self.width <= 32, self.name


@dataclass
class Block:
    """Readback window [base, base + 2^aw) of a block (memory or flag word).
    The shell drives port (port[index] for arrays) with the 32-bit word.
    write: the window is also written (lb_clk domain); the register file
    then outputs the write strobe wr_<port without rd_> ([index])."""
    name: str
    base: int
    aw: int
    width: int
    port: str
    index: Optional[int] = None
    signed: bool = False
    description: str = ''
    write: bool = False

    def __post_init__(self):
        assert self.base % (1 << self.aw) == 0, self.name
        assert self.port.startswith('rd_'), self.name

    @property
    def wr_port(self):
        return 'wr_' + self.port[len('rd_'):]


@dataclass
class Alias:
    """Register map entry over (part of) a window, with no decode of its own."""
    name: str
    base: int
    aw: int
    width: int
    signed: bool = False
    description: str = ''


def base_status():
    """Status words shared by the designs (step 7a: today's addresses)."""
    lb = [('rf_pwr_hi', 10), ('rf_pwr_lo', 10), ('rf_pwr_status', 10),
          ('rf_pwr_first_fault_status', 10), ('rf_pwr_latch', 10), ('rf_pwr_permit_sum', 1),
          ('arc_permit_raw', 3), ('arc_permit_latch', 3), ('arc_permit_sum', 1)]
    status = [Status(name, w, 1 + ix) for ix, (name, w) in enumerate(lb)]
    status += [Status(f'loop{n}_{x}_err', 15, 10 + 2 * n + ix, signed=True)
               for n in range(N_DRIVE) for ix, x in enumerate(('amp', 'phs'))]
    status += [Status('evr_evcnt', 32, 0x0e), Status('evr_ts_valid', 1, 0x0f),
               Status('evr_hb_valid', 1, 0x11), Status('evr_pps_valid', 1, 0x12),
               Status('evr_oc_valid', 1, 0x13), Status('evr_oc_frequency', 28, 0x14),
               Status('arc_testing', 1, 0x15)]
    # dsp_clk bank: evr_live_ts_lo must be slot 0, so the 64-bit timestamp
    # is read consistently (see jit_rad_gateway_demo.v)
    dsp = [('evr_live_ts_lo', 32, False), ('evr_live_ts_hi', 32, False),
           ('amp_setpoint_ntw', 18, True), ('phs_setpoint_ntw', 18, True),
           ('sig_buf_count', 32, False), ('ntw_cos_debug', 18, True), ('ntw_phase_debug', 19, True),
           ('trig_count', 32, False), ('fast_permit_out', 1, False), ('drive_permit_in', 1, False),
           ('slow_permit_in', 1, False), ('evg_permit_out', 1, False), ('hpa_permit_out', 1, False),
           ('drive_permit_out', 1, False)]
    status += [Status(name, w, 0x20 + ix, domain='dsp', signed=s) for ix, (name, w, s) in enumerate(dsp)]
    return status


def sig_buf_bases(sig_buf_aw):
    """Packed signal buffers (§1.1): raw ADC, then I and Q of the ADC and
    drive channels, each 2^sig_buf_aw deep, from SIG_BUF_BASE."""
    size, n_ch = 1 << sig_buf_aw, N_ADC + N_DRIVE
    raw = SIG_BUF_BASE
    i_base = raw + N_ADC * size
    q_base = i_base + n_ch * size
    assert q_base + n_ch * size <= MOD_BASE, f"signal buffers overrun 0x{MOD_BASE:x}"
    return raw, i_base, q_base


def base_blocks(sig_buf_aw=SIG_BUF_AW):
    """Readback windows shared by the designs."""
    sig = [f'adc{c}' for c in range(N_ADC)] + [f'drv{n}' for n in range(N_DRIVE)]
    size = 1 << sig_buf_aw
    raw, i_base, q_base = sig_buf_bases(sig_buf_aw)
    return [
        Block('llrf_circle_ready', 0x10800, 0, 2, 'rd_circle_ready'),
        Block('sig_buf_ready', 0x10801, 0, 8, 'rd_sig_buf_ready'),
        Block('sig_iq_buf_ready', 0x10802, 0, 20, 'rd_sig_iq_buf_ready'),
        Block('dsp_slow_data', 0x10900, 8, 16, 'rd_slow'),
        Block('mon_amp', 0x10a00, 4, 16, 'rd_mon_amp', signed=True),
        Block('mon_phs', 0x10a10, 4, 17, 'rd_mon_phs', signed=True),
        Block('fault_amp', 0x10a20, 4, 16, 'rd_fault_amp', signed=True,
              description='Monitor amplitude latched at the first fault, per channel'),
        *[Block(f'adc{c}_buf', raw + size * c, sig_buf_aw, 16, 'rd_adc_buf', c, signed=True)
          for c in range(N_ADC)],
        *[Block(f'{s}_i_buf', i_base + size * c, sig_buf_aw, 18, 'rd_sig_i_buf', c, signed=True)
          for c, s in enumerate(sig)],
        *[Block(f'{s}_q_buf', q_base + size * c, sig_buf_aw, 18, 'rd_sig_q_buf', c, signed=True)
          for c, s in enumerate(sig)],
        # modulation tables of loop n: amplitude, then phase (loop_ctrl)
        *[Block(f'loop{n}_{x}_mod', MOD_BASE + ((2 * n + ix) << MOD_AW), MOD_AW, 18, f'rd_{x}_mod', n,
                signed=True, write=True, description=f'loop {n} {x} modulation table')
          for n in range(N_DRIVE) for ix, x in enumerate(('amp', 'phs'))],
        Block('circle_data', CBUF_BASE, 16, 24, 'rd_cbuf', signed=True),
    ]


def base_aliases():
    return [
        # slow_bridge fields inside dsp_slow_data
        Alias('dsp_slow_cbuf_stat1', 0x10911, 0, 16),
        Alias('dsp_slow_cbuf_stat2', 0x10912, 0, 16),
        Alias('dsp_slow_cbuf_count', 0x10913, 0, 16),
        Alias('dsp_slow_tag', 0x10914, 0, 16),
        Alias('dsp_slow_tag_old', 0x10915, 0, 16),
        Alias('dsp_slow_adc_min', 0x10916, 3, 16, signed=True),
        Alias('dsp_slow_adc_max', 0x1091e, 3, 16, signed=True),
    ]


@dataclass
class RegMap:
    regs: list
    status: list
    blocks: list
    aliases: list
    sig_buf_aw: int = SIG_BUF_AW


def init_registers(regs):
    """Dataclass of the registers written at boot (init is not None), with
    their init values as defaults. Assignments are checked: unknown names
    and values that do not fit the register raise."""
    boot = {r.name: r for r in regs if r.init is not None}

    def setattr_checked(self, name, value):
        if name not in boot:
            raise AttributeError(f"{name} is not a boot-time register")
        object.__setattr__(self, name, boot[name].value(value))

    fields = [(r.name, int, dataclasses.field(default=r.init)) for r in boot.values()]
    return dataclasses.make_dataclass('LLRFInitRegisters', fields,
                                      namespace={'__setattr__': setattr_checked})


def insert_after(regs, name, new):
    """Insert the registers in new after the register called name."""
    ix = [r.name for r in regs].index(name) + 1
    regs[ix:ix] = new
    return regs


def check(regs):
    names = [r.name for r in regs]
    dup = sorted({n for n in names if names.count(n) > 1})
    assert not dup, f"duplicate registers {dup}"
    insts = [r.inst for r in regs if r.inst]
    assert insts == sorted(insts, key=insts.index), "instance registers must be contiguous"


def allocate(regs, base=RW_BASE):
    """Addresses as newad assigns them: largest tables first, then by name,
    each naturally aligned; the mirror covers the registers and tables of up
    to 2^MIRROR_MAX_AW entries. Returns ({name: addr}, mirror_base, mirror_aw)."""
    order = sorted(sorted(regs, key=lambda r: r.name), key=lambda r: r.aw, reverse=True)
    small = [r for r in order if r.aw <= MIRROR_MAX_AW]
    mirror_aw = sum(1 << r.aw for r in small).bit_length()
    mirror_base = None
    addr = {}
    for r in order:
        size = 1 << r.aw
        if mirror_base is None and r.aw <= MIRROR_MAX_AW:
            base = -(-base >> mirror_aw) << mirror_aw
            mirror_base = base
        base = -(-base >> r.aw) << r.aw
        addr[r.name] = base
        base += size
    assert mirror_base is not None, "no register to mirror"
    return addr, mirror_base, mirror_aw


def regmap_json(regs):
    addr, _, _ = allocate(regs)
    return {r.name: {'access': 'rw' if r.aw <= MIRROR_MAX_AW else 'w',
                     'addr_width': r.aw,
                     'base_addr': addr[r.name],
                     'data_width': r.width,
                     'description': r.description,
                     'sign': 'signed' if r.signed else 'unsigned'}
            for r in regs}


# --- generated outputs: llrf_shell_regmap_pkg.sv, llrf_shell_regs.sv and
# the whole llrf_shell.json

ROM_COMPAT = (0x800, 8)   # reads 0: old LEEP config ROM location


def shell_json(m):
    """llrf_shell.json: registers, status words, blocks and aliases."""
    def entry(access, base, aw, width, signed, description):
        return {'access': access, 'addr_width': aw, 'base_addr': base, 'data_width': width,
                'description': description, 'sign': 'signed' if signed else 'unsigned'}
    j = regmap_json(m.regs)
    for s in m.status:
        j[s.name] = entry('r', s.addr, 0, s.width, s.signed, s.description)
    for b in m.blocks + m.aliases:
        j[b.name] = entry('rw' if getattr(b, 'write', False) else 'r', b.base, b.aw, b.width, b.signed,
                          b.description)
    assert len(j) == len(m.regs) + len(m.status) + len(m.blocks) + len(m.aliases), "duplicate names"
    return j


def windows(m):
    """Readback windows (name, base, aw, rdata expression) of the lb_rd_mux."""
    _, mirror_base, mirror_aw = allocate(m.regs)
    banks = sorted({s.addr >> 4 for s in m.status})
    win = [(f'status_bank_{b:x}', b << 4, 4, f'status_bank_{b:x}') for b in banks]
    win += [('rom_compat', *ROM_COMPAT, "32'h0"), ('mirror', mirror_base, mirror_aw, 'mirror_out')]
    win += [(b.name, b.base, b.aw, b.port + ('' if b.index is None else f'[{b.index}]')) for b in m.blocks]
    spans = sorted((base, base + (1 << aw), name) for name, base, aw, _ in win)
    for (_, end, a), (start, _, b) in zip(spans, spans[1:]):
        assert end <= start, f"readback windows {a} and {b} overlap"
    return win


def field(name, width, signed=False):
    return f"        logic {'signed ' if signed else ''}[{width - 1}:0] {name};\n"


def pkg_sv(m, source):
    addr, _, mirror_aw = allocate(m.regs)
    out = [f"// Generated by uspas_llrf/regmap.py from {source}; do not edit.\n",
           "package llrf_shell_regmap_pkg;\n"]
    for dom in DOMAINS:
        regs = [r for r in m.regs if r.domain == dom and not r.aw]
        fields = "".join(field(r.name, r.width) for r in regs)
        out.append(f"    typedef struct packed {{\n{fields}    }} cfg_{dom}_t;\n")
    for dom in ('lb', 'dsp'):
        st = [s for s in m.status if s.domain == dom]
        fields = "".join(field(s.name, s.width, s.signed) for s in st)
        out.append(f"    typedef struct packed {{\n{fields}    }} status_{dom}_t;\n")
    out.append(f"    localparam int MIRROR_WIDTH = {mirror_aw};\n")
    out.append(f"    localparam int MAP_SIG_BUF_AW = {m.sig_buf_aw};  // signal buffer windows\n")
    out.append(f"    localparam int MAP_MOD_AW = {MOD_AW};  // modulation table windows\n")
    for r in m.regs:
        out.append(f"    localparam logic [{LB_HI}:0] ADDR_{r.name.upper()} = 18'h{addr[r.name]:05x};\n")
    for b in m.blocks:
        out.append(f"    localparam logic [{LB_HI}:0] ADDR_{b.name.upper()} = 18'h{b.base:05x};\n")
    out.append("endpackage\n")
    return "".join(out)


def ext32(expr, width, signed):
    """expr (width bits) extended to 32 bits."""
    if width == 32:
        return expr
    fill = f"{{{32 - width}{{{expr}[{width - 1}]}}}}" if signed else f"{32 - width}'b0"
    return f"{{{fill}, {expr}}}"


def decode_sv(r, addr):
    lb, msb, name = DOMAINS[r.domain], r.width - 1, r.name
    hit = f"({lb}_addr[{LB_HI}:{r.aw}] == {LB_HI + 1 - r.aw}'h{addr >> r.aw:x})"
    out = f"wire we_{name} = {lb}_write & {hit};\n"
    if r.aw:
        return out + (f"dpram #(.aw({r.aw}), .dw({r.width})) dp_{name} (\n"
                      f"    .clka({lb}_clk), .addra({lb}_addr[{r.aw - 1}:0]), .dina({lb}_data[{msb}:0]),"
                      f" .wena(we_{name}),\n"
                      f"    .clkb({lb}_clk), .addrb({name}_addr), .doutb({name}));\n")
    out += f"reg [{msb}:0] {name} = 0;\n"
    if r.kind == 'strobe':
        out += f"always @(posedge {lb}_clk) {name} <= we_{name} ? {lb}_data[{msb}:0] : {r.width}'b0;\n"
    else:
        out += f"always @(posedge {lb}_clk) if (we_{name}) {name} <= {lb}_data[{msb}:0];\n"
    return out + f"assign cfg_{r.domain}.{name} = {name};\n"


def regs_sv(m, source):
    addr, mirror_base, mirror_aw = allocate(m.regs)
    tables = [r for r in m.regs if r.aw]
    ports = {}
    for b in m.blocks:
        n = ports.setdefault(b.port, 0)
        ports[b.port] = max(n, 0 if b.index is None else b.index + 1)
    io = ["    input lb_clk,", f"    input [{LB_HI}:0] lb_addr,", "    input lb_write,", "    input lb_read,",
          "    input [31:0] lb_wdata,", "    input lb_prefill,", "    output [31:0] lb_rdata,",
          f"    output [{LB_HI}:0] lb_addr_d1,", "    input dsp_clk,", "    input dac_clk,", "    input gt_rxclk,"]
    io += [f"    output cfg_{dom}_t cfg_{dom}," for dom in DOMAINS]
    for r in tables:
        io += [f"    input [{r.aw - 1}:0] {r.name}_addr,", f"    output [{r.width - 1}:0] {r.name},"]
    io += ["    input status_lb_t status_lb,", "    input status_dsp_t status_dsp,",
           "    output xfer_snap,  // dsp_clk strobe: snapshot multi-word dsp status"]
    io += [f"    input [31:0] {p}" + (f" [{n}]" if n else "") + "," for p, n in ports.items()]
    wports = {}
    for b in m.blocks:
        if b.write:
            n = wports.setdefault(b.wr_port, 0)
            wports[b.wr_port] = max(n, 0 if b.index is None else b.index + 1)
    io += ["    output " + (f"[{n - 1}:0] " if n else "") + f"{p}," for p, n in wports.items()]
    io[-1] = io[-1].rstrip(',')
    out = [f"// Generated by uspas_llrf/regmap.py from {source}; do not edit.\n",
           "// rw registers (with the readback mirror), status words and the readback mux.\n",
           "module llrf_shell_regs\n    import llrf_shell_regmap_pkg::*;\n(\n", "\n".join(io), "\n);\n\n",
           "wire [31:0] lb_data = lb_wdata;\n",
           "wire lb1_clk = dsp_clk, lb2_clk = dac_clk, lb3_clk = gt_rxclk;\n",
           "wire lb1_write, lb2_write, lb3_write;\n",
           f"wire [{LB_HI}:0] lb1_addr, lb2_addr, lb3_addr;\n",
           "wire [31:0] lb1_data, lb2_data, lb3_data;\n",
           "lb_xdomain lb_xdomain (\n    .lb_clk(lb_clk), .lb_write(lb_write), .lb_addr(lb_addr), .lb_data(lb_data),\n"
           "    .lb1_clk(lb1_clk), .lb1_write(lb1_write), .lb1_addr(lb1_addr), .lb1_data(lb1_data),\n"
           "    .lb2_clk(lb2_clk), .lb2_write(lb2_write), .lb2_addr(lb2_addr), .lb2_data(lb2_data),\n"
           "    .lb3_clk(lb3_clk), .lb3_write(lb3_write), .lb3_addr(lb3_addr), .lb3_data(lb3_data)\n);\n\n"]
    out += [decode_sv(r, addr[r.name]) for r in m.regs]
    out.append(f"\n// readback mirror of the rw registers\nwire [31:0] mirror_out;\n"
               f"wire mirror_write = lb_write & (lb_addr[{LB_HI}:{mirror_aw}] =="
               f" {LB_HI + 1 - mirror_aw}'h{mirror_base >> mirror_aw:x});\n"
               f"dpram #(.aw({mirror_aw}), .dw(32)) mirror (\n"
               f"    .clka(lb_clk), .addra(lb_addr[{mirror_aw - 1}:0]), .dina(lb_data), .wena(mirror_write),\n"
               f"    .clkb(lb_clk), .addrb(lb_addr[{mirror_aw - 1}:0]), .doutb(mirror_out));\n")
    for bank in sorted({s.addr >> 4 for s in m.status}):
        st = [s for s in m.status if s.addr >> 4 == bank]
        dom = {s.domain for s in st}
        assert len(dom) == 1, f"status bank {bank:x} mixes domains"
        cases = "".join(f"        4'h{s.addr & 15:x}: status_bank_{bank:x} <= "
                        f"{ext32(f'status_{s.domain}.{s.name}', s.width, s.signed)};\n" for s in st)
        if dom == {'lb'}:
            out.append(f"\nreg [31:0] status_bank_{bank:x} = 0;\n"
                       f"always @(posedge lb_clk) if (lb_read) begin\n    case (lb_addr[3:0])\n{cases}"
                       f"        default: status_bank_{bank:x} <= 32'hfaceface;\n    endcase\nend\n")
        else:
            assert 'xfer_bank' not in "".join(out), "one dsp status bank only"
            out.append(f"\n// dsp_clk status: jit_rad == Just In Time Readout Across Domains\n"
                       f"wire xfer_clk, xfer_strobe, lb_error;\nwire [3:0] xfer_addr;\n"
                       f"reg [31:0] xfer_bank = 0;\nwire [31:0] status_bank_{bank:x};\n"
                       f"jit_rad_gateway #(.passthrough(0)) xfer_bank_gateway (\n"
                       f"    .lb_clk(lb_clk), .lb_addr(lb_addr[3:0]), .lb_strobe(lb_read),"
                       f" .lb_odata(status_bank_{bank:x}),\n"
                       f"    .lb_prefill(lb_prefill), .lb_error(lb_error),\n"
                       f"    .app_clk(dsp_clk), .xfer_clk(xfer_clk), .xfer_strobe(xfer_strobe),\n"
                       f"    .xfer_addr(xfer_addr), .xfer_odata(xfer_bank), .xfer_snap(xfer_snap)\n);\n"
                       f"always @(posedge xfer_clk) begin\n    case (xfer_addr)\n"
                       f"{cases.replace(f'status_bank_{bank:x} <=', 'xfer_bank <=')}"
                       f"        default: xfer_bank <= 32'hfaceface;\n    endcase\nend\n")
    wr = "".join(f"assign {b.wr_port}{'' if b.index is None else f'[{b.index}]'} = lb_write & "
                 f"(lb_addr[{LB_HI}:{b.aw}] == {LB_HI + 1 - b.aw}'h{b.base >> b.aw:x});  // {b.name}\n"
                 for b in m.blocks if b.write)
    if wr:
        out.append(f"\n// writes to the writable windows (lb_clk domain)\n{wr}")
    win = windows(m)
    bases = ", ".join(f"18'h{base:05x}" for _, base, _, _ in reversed(win))
    waws = ", ".join(f"5'd{aw}" for _, _, aw, _ in reversed(win))
    rdata = "".join(f"assign rd_win[{ix}] = {expr};  // {name}\n" for ix, (name, _, _, expr) in enumerate(win))
    out.append(f"\n// readback: window i covers [BASE[i], BASE[i] + 2^WAW[i])\n"
               f"wire [31:0] rd_win [{len(win)}];\n{rdata}"
               f"lb_rd_mux #(\n    .N({len(win)}),\n    .BASE({{{bases}}}),\n    .WAW({{{waws}}})\n) lb_rd_mux (\n"
               f"    .lb_clk(lb_clk), .lb_read(lb_read), .lb_addr(lb_addr), .rdata(rd_win),\n"
               f"    .lb_addr_d1(lb_addr_d1), .lb_rdata(lb_rdata)\n);\n\nendmodule\n")
    return "".join(out)


def design_file(design):
    """designs/<design>/design.py, or None if the design uses the base map."""
    if design is None:
        return None
    assert (DESIGNS_DIR / design).is_dir(), f"unknown design {design}"
    f = DESIGNS_DIR / design / 'design.py'
    return f if f.exists() else None


def design_scope(fname=None):
    """Namespace of designs/<d>/design.py (empty for the base map). It may
    define SIG_BUF_AW, design(rm) returning the registers and aliases(rm, m)
    returning extra aliases; rm is this module."""
    scope = {}
    if fname:
        with open(fname) as f:
            exec(compile(f.read(), str(fname), 'exec'), scope)
    return scope


def load_design(fname=None):
    """Registers of a design: design(rm) from fname, or the base map."""
    import sys
    rm = sys.modules[__name__]
    regs = design_scope(fname).get('design', lambda rm: rm.base_regs())(rm)
    check(regs)
    return regs


def load_map(fname=None):
    """Register map of a design: registers from load_design(), status words
    from the base, blocks with the design's SIG_BUF_AW, and aliases."""
    import sys
    scope = design_scope(fname)
    sig_buf_aw = scope.get('SIG_BUF_AW', SIG_BUF_AW)
    m = RegMap(load_design(fname), base_status(), base_blocks(sig_buf_aw), base_aliases(), sig_buf_aw)
    if 'aliases' in scope:
        m.aliases += scope['aliases'](sys.modules[__name__], m)
    windows(m)
    return m


def main():
    parser = argparse.ArgumentParser(description=(__doc__ or '').split('\n\n')[0])
    parser.add_argument('-d', '--design', help='design.py (default: base map)')
    parser.add_argument('-o', '--outdir', required=True, help='output directory')
    args = parser.parse_args()
    source = args.design or 'base_regs()'
    os.makedirs(args.outdir, exist_ok=True)
    m = load_map(args.design)
    for fname, text in (('llrf_shell_regmap_pkg.sv', pkg_sv(m, source)),
                        ('llrf_shell_regs.sv', regs_sv(m, source))):
        with open(os.path.join(args.outdir, fname), 'w') as f:
            f.write(text)
    with open(os.path.join(args.outdir, 'llrf_shell.json'), 'w') as f:
        json.dump(shell_json(m), f, sort_keys=True, indent=4, separators=(',', ': '))
        f.write('\n')


if __name__ == '__main__':
    main()
