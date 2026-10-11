#!/usr/bin/env python
"""C header with the localbus addresses of a leep JSON register map
(llrf_shell.json, marble_bsp.json).

Every entry gets #define NAME; arrays of up to 2^UNROLL_AW entries also get
NAME_0 .. NAME_<n-1> (the names the firmware and the ALSU Modbus map use).
"""
import argparse
import json
from pathlib import Path

UNROLL_AW = 6
LB_LIMIT = 0x01000000 >> 2   # localbus word addresses in the SoC window


def address_defines(regmap):
    """[(name, addr, info)] sorted by address, with arrays unrolled."""
    defines = []
    for key, info in regmap.items():
        addr = int(str(info["base_addr"]), 0)
        aw = info.get("addr_width", 0)
        if not (0 <= addr and addr + (1 << aw) <= LB_LIMIT):
            raise ValueError(f"{key}: address 0x{addr:x} (addr_width {aw}) outside the localbus")
        defines.append((key.upper(), addr, info))
        if 0 < aw <= UNROLL_AW:
            defines += [(f"{key.upper()}_{ix}", addr + ix, info) for ix in range(1 << aw)]
    names = [d[0] for d in defines]
    dup = sorted({n for n in names if names.count(n) > 1})
    if dup:
        raise ValueError(f"duplicate names {dup}")
    return sorted(defines, key=lambda d: (d[1], d[0]))


def generate_header(input_path, output_path, regmap):
    guard = f"_{Path(output_path).name.upper().replace('.', '_')}_"
    lines = [f"#define {name:40s} 0x{addr:05x}  // {info.get('access', 'rw')}, "
             f"{info.get('data_width', 32)}-bit" for name, addr, info in address_defines(regmap)]
    return (f"// Generated from {Path(input_path).name} by localbus_address_map.py; do not edit.\n"
            f"#ifndef {guard}\n#define {guard}\n\n" + "\n".join(lines) + f"\n\n#endif // {guard}\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument('-i', '--input', required=True, type=Path, help='JSON file')
    parser.add_argument('-o', '--output', required=True, type=Path, help='C header file')
    args = parser.parse_args()
    with open(args.input) as s:
        regmap = json.load(s)
    args.output.write_text(generate_header(args.input, args.output, regmap))
