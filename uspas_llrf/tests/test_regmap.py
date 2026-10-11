"""Register map checks (plan §2.4): the generated llrf_shell.json against the
step-1 baselines, the ALSU Modbus map, the boot-time registers of the model,
the allocator and the SoC address-map header script."""
import dataclasses
import importlib.util
import json
import re
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


def compat_errors(base, gen):
    """Differences in name, data_width, sign and access, apart from
    regmap.RENAMES and regmap.ADDITIONS."""
    errors = []
    for k, b in base.items():
        if k in gen:
            errors += [f"{k}: {f} {b.get(f)} -> {gen[k].get(f)}"
                       for f in ('data_width', 'sign', 'access') if b.get(f) != gen[k].get(f)]
        elif not all(n in gen for n in regmap.RENAMES.get(k, [None])):
            errors.append(f"{k}: missing")
    allowed = set(regmap.ADDITIONS) | {n for new in regmap.RENAMES.values() for n in new}
    errors += [f"{k}: not in the baseline" for k in gen if k not in base and k not in allowed]
    return errors


@pytest.mark.parametrize('design', [
    *DESIGNS[:-1],
    pytest.param('lemp', marks=pytest.mark.xfail(
        strict=True, reason="baseline is the LEMP-branch JSON; designs/lemp matches it after steps 9-10")),
])
def test_regmap_compat(design):
    base = json.loads((TOP / 'designs' / design / '_baseline' / 'llrf_shell.json').read_text())
    errors = compat_errors(base, build_json(design))
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
    assert init.wave_trig_sel is regmap.WaveTrigSel.Always and init.soft_drive_enable == 0b11


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


def test_readback_windows():
    """Every llrf_shell.json entry of the SV shell is inside a readback window
    of the generated mux (windows() also rejects overlapping windows)."""
    m = regmap.load_map()
    wins = [(base, base + (1 << aw)) for _, base, aw, _ in regmap.windows(m)]
    for name, e in regmap.shell_json(m).items():
        lo, hi = e['base_addr'], e['base_addr'] + (1 << e['addr_width'])
        covered = sum(min(hi, b) - max(lo, a) for a, b in wins if a < hi and lo < b)
        assert covered == hi - lo, f"{name}: [{lo:#x}, {hi:#x}) not fully decoded"
