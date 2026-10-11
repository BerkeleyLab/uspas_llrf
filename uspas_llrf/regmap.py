"""llrf_shell register map: declaration, address allocation and generated
outputs (plan §2.4). Replaces newad for llrf_shell.

The base map is base_regs(). A design extends it in designs/<d>/design.py,
which defines design(rm) returning the register list; rm is this module.

Outputs, written by the command line below:
- llrf_shell_regs.vh: register storage and decode (`LLRF_SHELL_REGS), the
  port connections of the block instances that own registers
  (`LLRF_SHELL_PORTS_<inst>) and the mirror readback dpram;
- regmap_llrf_shell.json: the register part of llrf_shell.json (leep schema).

Addresses, decode and mirror reproduce newad (newad.py -l -m -w 17
-b 0x11000), so the expanded shell and the JSON are unchanged (step 6).

This module uses the standard library only: the design build runs it as a
script, without importing the uspas_llrf package.
"""
import argparse
import json
import os
from dataclasses import dataclass

# register domain -> localbus copy in llrf_shell (data_xdomain from lb_clk)
DOMAINS = {'lb': 'lb', 'dsp': 'lb1', 'dac': 'lb2', 'evr': 'lb3'}
LB_HI = 17           # localbus address MSB (newad -w)
RW_BASE = 0x11000    # rw register window, mirrored for readback
MIRROR_MAX_AW = 5    # registers and tables up to 2^5 entries are mirrored
N_DRIVE = 2

# Renames and additions against the step-1 baseline JSON; test_regmap_compat
# allows exactly these differences (plan §2.4.1).
RENAMES = {
    'arc_test_arc_dev': ['arc_test_mask', 'arc_test_stb'],                # D18, step 3
}
ADDITIONS = ['arc_testing']                                               # D18, step 3


@dataclass
class Reg:
    """One rw register (aw == 0) or register table (aw > 0, a dpram).

    kind: 'rw' holds the written value; 'strobe' is high for one cycle
    after the write (newad single-cycle).
    inst: block instance whose port the register drives; the port name is
    the register name without the '<inst>_' prefix.
    """
    name: str
    width: int = 1
    domain: str = 'dsp'
    kind: str = 'rw'
    signed: bool = False
    aw: int = 0
    inst: str = None
    description: str = ''

    def __post_init__(self):
        assert self.domain in DOMAINS, (self.name, self.domain)
        assert self.kind in ('rw', 'strobe'), (self.name, self.kind)
        assert not (self.aw and self.kind != 'rw'), self.name
        assert not self.inst or self.name.startswith(self.inst + '_'), self.name

    @property
    def port(self):
        return self.name[len(self.inst) + 1:]


def loop_regs(n):
    w = 18
    return [Reg(f'loop{n}_amp_setpoint', w, signed=True),
            Reg(f'loop{n}_max_amp_setpoint', w, signed=True),
            Reg(f'loop{n}_phs_setpoint', w, signed=True),
            Reg(f'loop{n}_Kp_amp', w, signed=True),
            Reg(f'loop{n}_Kp_phs', w, signed=True),
            Reg(f'loop{n}_Ki_amp', w, signed=True),
            Reg(f'loop{n}_Ki_phs', w, signed=True),
            Reg(f'loop{n}_amp_enable'),
            Reg(f'loop{n}_phs_enable'),
            Reg(f'loop{n}_amp_reset'),
            Reg(f'loop{n}_phs_reset')]


def base_regs():
    """Registers shared by all designs, in the order of the decode."""
    regs = [
        Reg('circle_buf_flip', domain='lb', kind='strobe'),
        Reg('sig_buf_flip', domain='lb', kind='strobe'),
        Reg('dsp_tag', 8),
        Reg('cbuf_post_delay', 16),
        Reg('wave_samp_per', 7),
        Reg('chan_keep', 10),
        Reg('cic_base_period', 7),
        Reg('cic_wave_shift', 4),
        Reg('inlk_wave_shift', 4),
        Reg('inlk_permit_mask', 10),
        Reg('arc_permit_mask', 8),
        Reg('rx_dds_phase_step', 32),
        Reg('rx_dds_phase_shift', 19, signed=True),
        Reg('rx_dds_modulo', 12),
        Reg('rx_dds_amplitude', 18),
        Reg('rx_phase_offset', 19, signed=True),
        Reg('tx_phase_offset', 19, signed=True),
        Reg('prl_adc_chan', 3),
        *[Reg(f'loop{n}_adc_chan', 3) for n in range(N_DRIVE)],
        *[r for n in range(N_DRIVE) for r in loop_regs(n)],
        Reg('dsp_reset', kind='strobe'),
        *[Reg(f'loop{n}_pulse_{f}', 24) for n in range(N_DRIVE) for f in ('start', 'high_len')],
        Reg('pulse_modes', N_DRIVE),
        Reg('soft_drive_enable', N_DRIVE),
        Reg('ntw_amp_enable'),
        Reg('ntw_phs_enable'),
        Reg('system_bist_pass'),
        Reg('wave_trig_sel', 3),
        Reg('trigger_delay', 24),
        Reg('int_trigger_period', 32),
        Reg('soft_trigger', kind='strobe'),
        Reg('slow_snap_cic'),
        Reg('ext_permit_bypass'),
        Reg('dac_drive_sel', 2, domain='dac'),
        Reg('tx_dds_phase_step', 32, domain='dac'),
        Reg('tx_dds_phase_shift', 19, domain='dac', signed=True),
        Reg('tx_dds_modulo', 12, domain='dac'),
        Reg('tx_dds_amplitude', 18, domain='dac'),
        Reg('duc_spectral_flip', domain='dac'),
        Reg('tx_afe_spectral_flip', domain='dac'),
        Reg('evcode', 8, domain='evr'),
        Reg('evr_oc_delay', 7, domain='evr'),
        # monitor_inlk inlk
        Reg('inlk_amp_lo', 16, aw=4, inst='inlk'),
        Reg('inlk_amp_hi', 16, aw=4, inst='inlk'),
        Reg('inlk_reset_inlk', kind='strobe', inst='inlk'),
        Reg('inlk_inlk_mode', 2, aw=4, inst='inlk'),
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


def write_json(regs, fname):
    with open(fname, 'w') as f:
        json.dump(regmap_json(regs), f, sort_keys=True, indent=4, separators=(',', ': '))
        f.write('\n')


def addr_hit(r, addr):
    lb = DOMAINS[r.domain]
    pattern = (addr & ((1 << (LB_HI + 1)) - 1)) >> r.aw
    return f"`define ADDR_HIT_{r.name} ({lb}_addr[`LB_HI:{r.aw}]=={pattern})\n"


def decode(r):
    """Storage and write decode of one register, as newad emits it."""
    lb, msb = DOMAINS[r.domain], r.width - 1
    we = f"wire we_{r.name} = {lb}_write&(`ADDR_HIT_{r.name});\\\n"
    if r.aw:
        wires = f"wire [{r.aw - 1}:0] {r.name}_addr;\\\nwire [{msb}:0] {r.name};\\\n"
        return (wires + we + f"dpram #(.aw({r.aw}),.dw({r.width})) dp_{r.name}(\\\n"
                f"\t.clka({lb}_clk), .addra({lb}_addr[{r.aw - 1}:0]), .dina({lb}_data[{msb}:0]),"
                f" .wena(we_{r.name}),\\\n"
                f"\t.clkb({lb}_clk), .addrb({r.name}_addr), .doutb({r.name}));\\\n")
    decl = f"reg [{msb}:0] {r.name}=0;"
    if r.kind == 'strobe':
        return we + (f"{decl} always @(posedge {lb}_clk) {r.name} <= we_{r.name} ?"
                     f" {lb}_data[{msb}:0] : {r.width}'b0;\\\n")
    return we + f"{decl} always @(posedge {lb}_clk) if (we_{r.name}) {r.name} <= {lb}_data;\\\n"


def ports(regs, inst):
    conns = []
    for r in regs:
        if r.inst == inst:
            conns.append(f".{r.port}({r.name})")
            if r.aw:
                conns.append(f".{r.port}_addr({r.name}_addr)")
    return f"`define LLRF_SHELL_PORTS_{inst} " + ",\\\n\t".join(conns) + "\n"


def mirror():
    return ("wire [31:0] mirror_out_0;wire mirror_write_0 = lb_write &(`ADDR_HIT_MIRROR);\\\n"
            "dpram #(.aw(`MIRROR_WIDTH),.dw(32)) mirror_0(\\\n"
            "\t.clka(lb_clk), .addra(lb_addr[`MIRROR_WIDTH-1:0]), .dina(lb_data[31:0]),"
            " .wena(mirror_write_0),\\\n"
            "\t.clkb(lb_clk), .addrb(lb_addr[`MIRROR_WIDTH-1:0]), .doutb(mirror_out_0));\\\n")


def regs_vh(regs, source):
    addr, mirror_base, mirror_aw = allocate(regs)
    out = [f"// Generated by uspas_llrf/regmap.py from {source}; do not edit.\n",
           f"`define LB_HI {LB_HI}\n",
           f"`define MIRROR_WIDTH {mirror_aw}\n",
           f"`define ADDR_HIT_MIRROR (lb_addr[`LB_HI:`MIRROR_WIDTH]=={mirror_base >> mirror_aw})\n"]
    out += [addr_hit(r, addr[r.name]) for r in regs]
    for inst in dict.fromkeys(r.inst for r in regs if r.inst):
        out.append(ports(regs, inst))
    out.append("`define LLRF_SHELL_REGS\\\n" + "".join(decode(r) for r in regs) + mirror() + "\n")
    return "".join(out)


def load_design(fname=None):
    """Registers of a design: design(rm) from fname, or the base map."""
    import sys
    rm = sys.modules[__name__]
    if not fname:
        regs = base_regs()
    else:
        scope = {}
        with open(fname) as f:
            exec(compile(f.read(), fname, 'exec'), scope)
        regs = scope['design'](rm)
    check(regs)
    return regs


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('-d', '--design', help='design.py (default: base map)')
    parser.add_argument('-o', '--outdir', required=True, help='output directory')
    args = parser.parse_args()
    regs = load_design(args.design)
    os.makedirs(args.outdir, exist_ok=True)
    with open(os.path.join(args.outdir, 'llrf_shell_regs.vh'), 'w') as f:
        f.write(regs_vh(regs, args.design or 'base_regs()'))
    write_json(regs, os.path.join(args.outdir, 'regmap_llrf_shell.json'))


if __name__ == '__main__':
    main()
