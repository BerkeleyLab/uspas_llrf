"""Register map checks (plan §2.4): the generated llrf_shell.json against the
step-1 baselines, the ALSU Modbus map, the boot-time registers of the model,
the allocator, the SoC address-map header script and the block config
structs."""
import dataclasses
import importlib.util
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

from uspas_llrf import regmap

try:
    import tomllib
except ImportError:  # Python < 3.11
    import tomli as tomllib

TOP = Path(__file__).resolve().parents[2]
DESIGNS = ['uspas', 'awa', 'pip-ii', 'alsu', 'lemp']


def build_json(design):
    d = TOP / 'designs' / design
    subprocess.run(['make', '-s', '-C', str(d), f'PYTHON={sys.executable}', 'llrf_shell.json'],
                   check=True, stdout=subprocess.DEVNULL)
    return json.loads((d / 'llrf_shell.json').read_text())


def compat_errors(base, gen, scope=None):
    """Differences in name, data_width, sign and access, apart from
    regmap.RENAMES, regmap.ADDITIONS, regmap.REMOVALS and regmap.WIDTH_CHANGES,
    and the design's COMPAT_REMOVALS, COMPAT_ADDITIONS and COMPAT_CHANGES
    ({name: (data_width, sign)}) from design.py (scope). Addresses and
    addr_width may change (D1, D5)."""
    scope = scope or {}
    removals = set(regmap.REMOVALS) | set(scope.get('COMPAT_REMOVALS', []))
    changes = scope.get('COMPAT_CHANGES', {})
    errors = []
    for k, b in base.items():
        if k in gen:
            if k in changes and (gen[k].get('data_width'), gen[k].get('sign')) == changes[k]:
                continue
            errors += [f"{k}: {f} {b.get(f)} -> {gen[k].get(f)}"
                       for f in ('data_width', 'sign', 'access') if b.get(f) != gen[k].get(f)
                       and not (f == 'data_width' and regmap.WIDTH_CHANGES.get(k) == gen[k].get(f))]
        elif k not in removals and not all(n in gen for n in regmap.RENAMES.get(k, [None])):
            errors.append(f"{k}: missing")
    allowed = set(regmap.ADDITIONS) | set(scope.get('COMPAT_ADDITIONS', []))
    allowed |= {n for new in regmap.RENAMES.values() for n in new}
    errors += [f"{k}: not in the baseline" for k in gen if k not in base and k not in allowed]
    return errors


@pytest.mark.parametrize('design', DESIGNS)
def test_regmap_compat(design):
    """The design's map against its step-1 baseline; LEMP's baseline is the
    LEMP-branch map (2e25cd9), its intended differences are in design.py."""
    base = json.loads((TOP / 'designs' / design / '_baseline' / 'llrf_shell.json').read_text())
    scope = regmap.design_scope(regmap.design_file(design))
    errors = compat_errors(base, build_json(design), scope)
    assert not errors, "\n".join(errors)


def test_modbus_names():
    """Every leep_name in the ALSU Modbus map exists in ALSU's JSON."""
    gen = build_json('alsu')
    with open(TOP / 'soc' / 'alsu' / 'mb_addr_map.toml', 'rb') as f:
        mb = tomllib.load(f)
    missing = [f"{mb_name} = {entry}" for section in mb.values() for mb_name, entry in section.items()
               if entry[0] != 0 and (entry[0] not in gen or entry[1] >= 1 << gen[entry[0]]['addr_width'])]
    assert not missing, "\n".join(missing)


def design_fset(design):
    """FSET of a design, from settings.mk (FSET_<design> = <FSET>)."""
    for line in (TOP / 'settings.mk').read_text().splitlines():
        m = re.match(rf"FSET_{re.escape(design)}\s*=\s*(\w+)", line)
        if m:
            return m.group(1)
    raise KeyError(design)


@pytest.mark.parametrize('design', DESIGNS)
def test_init_registers(design):
    """The boot-time registers come from the design's register map, and every
    value the model derives from the design's FSET fits its register (the
    LLRFInitRegisters assignments check it)."""
    from uspas_llrf import dsp_config, LLRFShell
    model = LLRFShell(dsp_config[design_fset(design)], design=design)
    boot = [r.name for r in model.regs if r.init is not None]
    assert list(dataclasses.asdict(model.init_regs)) == boot


def test_init_register_checks():
    regs = regmap.base_regs()
    init = regmap.init_registers(regs)()
    init.chan_keep = 0x3ff
    with pytest.raises(ValueError, match='chan_keep'):
        init.chan_keep = 0x400
    with pytest.raises(ValueError, match='loop0_amp_setpoint'):
        init.loop0_amp_setpoint = -(1 << 17) - 1
    with pytest.raises(ValueError):
        init.wave_trig_sel = 7
    with pytest.raises(AttributeError, match='dsp_reset'):
        init.dsp_reset = 1
    assert init.wave_trig_sel is regmap.WaveTrigSel.Always and init.soft_drive0_enable == init.soft_drive1_enable == 1


@pytest.mark.parametrize('design', DESIGNS)
def test_allocation(design):
    """rw registers are naturally aligned, do not overlap and sit in the mirror."""
    design_py = TOP / 'designs' / design / 'design.py'
    regs = regmap.load_design(design_py if design_py.exists() else None)
    addr, mirror_base, mirror_aw = regmap.allocate(regs)
    assert mirror_base == regmap.RW_BASE
    used = set()
    for r in regs:
        a, size = addr[r.name], 1 << r.aw
        assert a % size == 0, r.name
        assert mirror_base <= a and a + size <= mirror_base + (1 << mirror_aw), r.name
        span = set(range(a, a + size))
        assert not used & span, r.name
        used |= span


def load_header_script():
    path = TOP / 'soc' / 'common' / 'llrf' / 'localbus_address_map.py'
    spec = importlib.util.spec_from_file_location('localbus_address_map', path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_address_header():
    lam = load_header_script()
    regmap_ = {'mon_phs': {'base_addr': '0x10a10', 'addr_width': 4, 'access': 'r', 'data_width': 17},
               'big_buf': {'base_addr': 0x12000, 'addr_width': 12, 'access': 'r', 'data_width': 16},
               'dsp_tag': {'base_addr': 0x11035, 'addr_width': 0, 'access': 'rw', 'data_width': 8}}
    names = {name: addr for name, addr, _ in lam.address_defines(regmap_)}
    assert names['MON_PHS'] == names['MON_PHS_0'] == 0x10a10 and names['MON_PHS_15'] == 0x10a1f
    assert names['BIG_BUF'] == 0x12000 and 'BIG_BUF_0' not in names
    assert names['DSP_TAG'] == 0x11035
    with pytest.raises(ValueError, match='duplicate'):
        lam.address_defines({**regmap_, 'mon_phs_0': regmap_['dsp_tag']})
    with pytest.raises(ValueError, match='outside'):
        lam.address_defines({'x': {'base_addr': lam.LB_LIMIT, 'addr_width': 0}})


@pytest.mark.parametrize('design', DESIGNS)
def test_readback_windows(design):
    """Every llrf_shell.json entry of the SV shell is inside a readback window
    of the generated mux (windows() also rejects overlapping windows). An
    alias such as LEMP's iq_buf may also cover unmapped space, but of the
    decoded windows only signal buffers, whole (§2.4)."""
    m = regmap.load_map(regmap.design_file(design))
    wins = [(name, base, base + (1 << aw)) for name, base, aw, _ in regmap.windows(m)]
    aliases = {a.name for a in m.aliases}
    for name, e in regmap.shell_json(m).items():
        lo, hi = e['base_addr'], e['base_addr'] + (1 << e['addr_width'])
        hits = [(w, a, b) for w, a, b in wins if a < hi and lo < b]
        if name in aliases and e['addr_width'] > 0 and name.endswith('_buf'):
            for w, a, b in hits:
                assert w.endswith('_buf') and lo <= a and b <= hi, f"{name} covers part of {w}"
            continue
        covered = sum(min(hi, b) - max(lo, a) for _, a, b in hits)
        assert covered == hi - lo, f"{name}: [{lo:#x}, {hi:#x}) not fully decoded"


# --- block config structs: <inst>_cfg_t in llrf_shell_pkg.sv ---------------

PKG = TOP / 'llrf_dsp' / 'llrf_shell_pkg.sv'
CFG_STRUCT = re.compile(r"typedef struct packed \{(.*?)\}\s*(\w+)_cfg_t;", re.S)
CFG_MEMBER = re.compile(r"^\s*logic\s+(signed\s+)?(?:\[([\w+\- ]+):(\d+)\])?\s*(\w+);[ \t]*(//\s*strobe)?", re.M)


def pkg_params(text):
    """{name: value} of the integer localparams in text."""
    return {m[1]: int(m[2]) for m in re.finditer(r"localparam int (\w+) = (\d+);", text)}


def cfg_structs(text):
    """{inst: {member: (width, signed, strobe)}} of the <inst>_cfg_t types in
    text; a member's MSB may use the package's localparams (PULSE_AW-1)."""
    params = pkg_params(text)

    def msb(expr):  # N, NAME or NAME+-N
        m = re.fullmatch(r"\s*(\w+)\s*(?:([+-])\s*(\d+))?\s*", expr)
        assert m, expr
        base = int(m[1]) if m[1].isdigit() else params[m[1]]
        return base + (int(m[3]) if m[2] == '+' else -int(m[3]) if m[2] else 0)
    return {m[2]: {f[4]: (msb(f[2]) - int(f[3]) + 1 if f[2] else 1, bool(f[1]), bool(f[5]))
                   for f in CFG_MEMBER.finditer(m[1])}
            for m in CFG_STRUCT.finditer(text)}


@pytest.mark.parametrize('design', DESIGNS)
def test_cfg_structs(design):
    """The registers of each block instance are the members of its
    <inst>_cfg_t: same names (a mismatch also fails to compile), widths,
    signedness and kind (`// strobe` members are strobe registers). The monitor_inlk tables
    have INLK_AW address bits."""
    regs = regmap.load_design(regmap.design_file(design))
    text = PKG.read_text()
    structs = cfg_structs(text)
    errors = []
    for inst, elements in regmap.inst_cfgs(regs).items():
        members = structs.get(inst)
        if members is None:
            errors.append(f"instance {inst}: no {inst}_cfg_t in {PKG.name}")
            continue
        for rs in elements:
            got = {r.port: (r.width, r.signed, r.kind == 'strobe') for r in rs}
            errors += [f"{inst}_cfg_t.{p}: (width, signed, strobe) {members.get(p)}, register {rs[0].prefix}{p} {v}"
                       for p, v in got.items() if members.get(p) != v]
            errors += [f"{inst}_cfg_t.{p}: no register" for p in members if p not in got]
    inlk_aw = pkg_params(text)['INLK_AW']
    errors += [f"{r.name}: aw {r.aw}, INLK_AW {inlk_aw}" for r in regs if r.inst == 'inlk' and r.aw and r.aw != inlk_aw]
    assert not errors, "\n".join(errors)


def test_inst_array(tmp_path):
    """Indexed registers make an array of the instance's config struct,
    cfg_<domain>.<inst>[k], each element assigned as a named pattern; sv2v
    accepts the generated package and register file. Elements must have
    the same members."""
    m = regmap.load_map()
    m.regs += [regmap.Reg(f'trg_{k}_{p}', 32, inst='trg', index=k) for k in range(2) for p in ('width', 'delay')]
    regmap.check(m.regs)
    pkg, regs = regmap.pkg_sv(m, 'test'), regmap.regs_sv(m, 'test')
    assert "        trg_cfg_t [1:0] trg;\n" in pkg
    assert "assign cfg_dsp.trg[1] = '{width: trg_1_width, delay: trg_1_delay};\n" in regs
    with pytest.raises(AssertionError, match="elements of instance trg differ"):
        regmap.check(m.regs[:-1])
    sv2v = shutil.which('sv2v')
    if sv2v is None:
        pytest.skip("sv2v not found")
    typedef = "    typedef struct packed { logic [31:0] width; logic [31:0] delay; } trg_cfg_t;\n"
    files = {'llrf_shell_pkg.sv': PKG.read_text().replace("endpackage", typedef + "endpackage"),
             'llrf_shell_regmap_pkg.sv': pkg, 'llrf_shell_regs.sv': regs}
    for name, text in files.items():
        (tmp_path / name).write_text(text)
    r = subprocess.run([sv2v, *(str(tmp_path / f) for f in files)], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr


def test_wave_trig_encoding():
    """WaveTrigSel (Python) and the WAVE_TRIG_* constants of llrf_shell_pkg.sv
    are the same encoding (plan L4)."""
    names = {'INT': 'Internal', 'EXT': 'External', 'SOFT': 'Software', 'EVR': 'EVR',
             'ALWAYS': 'Always', 'MIXED': 'Mixed', 'FIDUCIAL': 'Fiducial'}
    rtl = {names[m[1]]: int(m[2]) for m in re.finditer(r"WAVE_TRIG_(\w+)\s*=\s*3'd(\d+)", PKG.read_text())}
    assert rtl == {e.name: e.value for e in regmap.WaveTrigSel}
