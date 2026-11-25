#!/usr/bin/env python3
"""Check the merged register map against the board top's localbus decode.

The top (top/common/marble_zest_mid.vh, and a design's design_mid.vh) splits
the localbus into segments by lb_addr[21:18]: it gives each block the write
and read strobes of one segment, reads its data back through a case on the
segment, and overlays the git ID and the config ROM on the shell's segment.
merge_json.py checks that names are unique; this checks the addresses.

  - each block JSON's module is instantiated once, with the write strobe, the
    read strobe and the read data of the same segment, and that segment is
    read back (under the build's defines);
  - every register of a block lies in that segment;
  - the overlays (git_rev_id, llrf_rom in marble_zest_top.json) are exactly
    where the top decodes them, and no block register lies under one, where
    reads would return the overlay;
  - no two blocks' registers overlap.

A typed block (llrf_shell) takes an lb_req_t, `.lb_req(lb_req_0)`; the
check then reads the write and read strobes from lb_req_0's assignment
pattern (`assign lb_req_0 = '{write: lb_write_0, read: lb_read_0, ...}`).

A block JSON is named after its module (llrf_shell.json, marble_bsp.json,
interlock_wrapper.json); marble_zest_top.json holds the overlays.
"""
import argparse
import json
import os
import re
import sys

TOP_JSON = 'marble_zest_top'


def strip_comments(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return re.sub(r'//[^\n]*', '', text)


def preprocess(text, defines):
    """Keep the lines that `ifdef/`ifndef/`else/`endif select."""
    out, stack = [], []
    for line in text.splitlines():
        m = re.match(r'\s*`(ifdef|ifndef|else|endif)\b\s*(\w*)', line)
        if m:
            kw, name = m.groups()
            if kw in ('ifdef', 'ifndef'):
                stack.append((name in defines) == (kw == 'ifdef'))
            elif kw == 'else':
                stack[-1] = not stack[-1]
            else:
                stack.pop()
            continue
        if all(stack):
            out.append(line)
    return '\n'.join(out)


def num(lit):
    """A Verilog number: 22'h0, 4'h2, 11'b00_0000_0100_0, 7."""
    m = re.fullmatch(r"(?:\d+)?'([hbdo])([0-9a-fA-F_xXzZ]+)|(\d+)", lit.strip())
    if not m:
        raise ValueError(f'not a number: {lit}')
    if m.group(3):
        return int(m.group(3))
    return int(m.group(2).replace('_', ''), {'h': 16, 'b': 2, 'd': 10, 'o': 8}[m.group(1)])


def instances(text):
    """{module: [instance text]} for instances with a .lb_rdata port."""
    out = {}
    for m in re.finditer(r'\.lb_rdata\s*\(', text):
        # the instance header: the last `module [#(...)] name (` before the port
        head = None
        for h in re.finditer(r'^(\w+)\s*(?:#\s*\(|\w+\s*\()', text[:m.start()], flags=re.M):
            if h.group(1) not in ('module', 'assign', 'wire', 'reg', 'always', 'initial'):
                head = h
        end = text.index(');', m.end())
        out.setdefault(head.group(1), []).append(text[head.start():end])
    return out


def port(inst, name):
    m = re.search(r'\.' + name + r'\s*\(\s*([\w\[\]:]+)\s*\)', inst)
    return m.group(1) if m else None


def decode(text, defines):
    text = preprocess(strip_comments(text), defines)
    m = re.search(r'lb_addr_mux\s*=\s*lb_addr\[(\d+)\s*\+:\s*(\d+)\]', text)
    seg_shift = int(m.group(1))
    # the readback case: segment -> read data net
    case = re.search(r'case\s*\(\s*lb_addr_mux\s*\)(.*?)endcase', text, flags=re.S).group(1)
    read = {num(s): net for s, net in re.findall(r"([\w']+)\s*:\s*lb_rdata_r\s*=\s*(\w+)\s*;", case)}
    # per-segment strobes: lb_write_N = lb_write & lb_base_N, lb_base_N = (mux == N)
    base = {b: num(v) for b, v in re.findall(r'wire\s+(lb_base_\w+)\s*=\s*\(\s*lb_addr_mux\s*==\s*([\w\']+)\s*\)', text)}
    strobe = {}
    for kind in ('write', 'read'):
        for s, b in re.findall(r'wire\s+(lb_%s_\w+)\s*=\s*lb_%s\s*&\s*(lb_base_\w+)' % (kind, kind), text):
            strobe[s] = base[b]
    # overlays: name_sel = (lb_addr == N) or (lb_addr[H:L] == V), and the
    # name they select in the lb_rdata assignment
    overlays = []
    for sel, expr in re.findall(r'wire\s+(\w+_sel)\s*=\s*\((.*?)\)\s*;', text):
        m = re.fullmatch(r'\s*lb_addr\s*(?:\[(\d+):(\d+)\])?\s*==\s*([\w\']+)\s*', expr)
        if not m:
            continue
        lsb = int(m.group(2) or 0)
        overlays.append((sel, num(m.group(3)) << lsb, 1 << lsb))
    # lb_req_t structs built from strobes: name -> {field: net}
    reqs = {}
    for name, fields in re.findall(r"assign\s+(\w+)\s*=\s*'\{(.*?)\}\s*;", text, flags=re.S):
        reqs[name] = dict(re.findall(r'(\w+)\s*:\s*([\w\[\]:]+)', fields))
    return seg_shift, read, strobe, overlays, instances(text), reqs


def entries(fn):
    with open(fn) as f:
        d = json.load(f)
    out = {}
    for k, v in d.items():
        b = v['base_addr']
        b = int(b, 0) if isinstance(b, str) else b
        out[k] = (b, 1 << v.get('addr_width', 0))
    return out


def check(vh_files, block_jsons, merged_json, defines):
    errors = []
    text = ''.join(open(f).read() + '\n' for f in vh_files)
    seg_shift, read, strobe, overlays, insts, reqs = decode(text, defines)
    seg_size = 1 << seg_shift
    merged = entries(merged_json)
    owner = {}
    for fn in block_jsons:
        block = os.path.splitext(os.path.basename(fn))[0]
        for k in entries(fn):
            owner[k] = block
    # merge_json.py expands arrays of up to 4 registers into name_0..name_3
    for k in merged:
        if k not in owner:
            base = re.sub(r'_\d+$', '', k)
            if base in owner:
                owner[k] = owner[base]
            else:
                errors.append(f'{k}: in {merged_json} but in no block JSON')
    seg_of = {}
    for fn in block_jsons:
        block = os.path.splitext(os.path.basename(fn))[0]
        if block == TOP_JSON:
            continue
        found = insts.get(block, [])
        if len(found) != 1:
            errors.append(f'{block}: {len(found)} instances with a localbus in the top, expected 1')
            continue
        inst = found[0]
        rdata, write, rd = port(inst, 'lb_rdata'), port(inst, 'lb_write'), port(inst, 'lb_read')
        req = port(inst, 'lb_req')  # a typed block (llrf_shell): the strobes are lb_req_t fields
        if req is not None:
            if req not in reqs:
                errors.append(f'{block}: .lb_req({req}) is not assigned from an assignment pattern')
                continue
            write, rd = reqs[req].get('write'), reqs[req].get('read')
        segs = [s for s, net in read.items() if net == rdata]
        seg = segs[0] if len(segs) == 1 else None
        if seg is None:
            errors.append(f'{block}: its read data {rdata} is not read back in the lb_addr_mux case')
            continue
        for name, net in (('lb_write', write), ('lb_read', rd)):
            if strobe.get(net) != seg:
                errors.append(f'{block}: .{name}({net}) is not the strobe of segment {seg} (its read data {rdata})')
        seg_of[block] = seg
        print(f'{block}: segment {seg} ({seg * seg_size:#x}..{(seg + 1) * seg_size - 1:#x})')
    # the overlays: marble_zest_top.json entries exactly on a decoded overlay
    spans = {(b, n) for _, b, n in overlays}
    for k, (b, n) in merged.items():
        if owner.get(k) == TOP_JSON and (b, n) not in spans:
            errors.append(f'{k}: {b:#x}+{n:#x} is not an overlay the top decodes '
                          f'({", ".join(f"{s} {b:#x}+{n:#x}" for s, b, n in overlays)})')
    # every block register in its segment and not under an overlay
    for k, (b, n) in merged.items():
        block = owner.get(k)
        if block == TOP_JSON or block not in seg_of:
            continue
        seg = seg_of[block]
        if b // seg_size != seg or (b + n - 1) // seg_size != seg:
            errors.append(f'{k} ({block}): {b:#x}..{b + n - 1:#x} is not in segment {seg}')
        for sel, ob, on in overlays:
            if b < ob + on and ob < b + n:
                errors.append(f'{k} ({block}): {b:#x}..{b + n - 1:#x} lies under the {sel} overlay')
    # no overlap between blocks
    spans = sorted((b, b + n, k, owner.get(k)) for k, (b, n) in merged.items() if owner.get(k) != TOP_JSON)
    reach = None
    for b, e, k, blk in spans:
        if reach and b < reach[0] and blk != reach[2]:
            errors.append(f'{k} ({blk}) overlaps {reach[1]} ({reach[2]})')
        if not reach or e > reach[0]:
            reach = (e, k, blk)
    return errors


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('-m', '--merged', required=True, help='merged JSON (merge_json.py output)')
    ap.add_argument('-j', '--json', nargs='+', required=True, help='block JSONs, named after their modules')
    ap.add_argument('-v', '--verilog', nargs='+', required=True, help='marble_zest_mid.vh, design_mid.vh')
    ap.add_argument('-D', '--define', action='append', default=[], help='defines of the build (NAME or NAME=value)')
    args = ap.parse_args()
    defines = {d.split('=')[0] for d in args.define}
    errors = check(args.verilog, args.json, args.merged, defines)
    for e in errors:
        print('ERROR:', e, file=sys.stderr)
    if errors:
        sys.exit(1)
    print(f'{args.merged}: addresses match the localbus decode')


if __name__ == '__main__':
    main()
