"""Register map checks (plan §2.4): the generated llrf_shell.json against the
step-1 baselines, the ALSU Modbus map and LLRFInitRegisters, plus the
allocator and the SoC address-map header script."""
import dataclasses
import importlib.util
import json
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


def test_init_registers():
    """Every LLRFInitRegisters field is a register whose width holds its default."""
    from uspas_llrf.model.llrf_shell import LLRFShell
    regs = {r.name: r for r in regmap.base_regs()}
    errors = []
    for f in dataclasses.fields(LLRFShell.LLRFInitRegisters):
        r = regs.get(f.name)
        if r is None:
            errors.append(f"{f.name}: not a register")
            continue
        lo, hi = (-(1 << (r.width - 1)), 1 << (r.width - 1)) if r.signed else (0, 1 << r.width)
        if not lo <= int(f.default) < hi:
            errors.append(f"{f.name}: default {f.default} does not fit {r.width} bits")
    assert not errors, "\n".join(errors)


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
