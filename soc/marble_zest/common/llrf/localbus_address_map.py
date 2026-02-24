#!/usr/bin/env python
import json
from pathlib import Path
import argparse


def format_register_define(name: str, info: dict) -> str:
    addr = info["base_addr"]
    width = info.get("data_width", 32)
    access = info.get("access", "rw")
    return f"#define {name.upper():40s} 0x{addr:05x}  // {access}, {width}-bit"


def generate_header(input_path: Path, regmap: dict) -> str:
    guard = f"_{Path(input_path).name.upper().replace('.', '_')}_"

    sorted_registers = sorted(
        regmap.items(), key=lambda item: item[1]["base_addr"])
    defines = "\n".join(
        format_register_define(name, info) for name, info in sorted_registers
    )

    return (
        f"// Auto-generated from {input_path}\n"
        f"#ifndef {guard}\n"
        f"#define {guard}\n"
        f"\n"
        f"{defines}\n"
        f"\n"
        f"#endif // {guard}\n"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('-i', '--input', required=True,
                        type=Path, help='JSON file')
    parser.add_argument('-o', '--output', required=True,
                        type=Path, help='C header file')
    args = parser.parse_args()

    with open(args.input) as s:
        regmap = json.load(s)
    header = generate_header(args.input, regmap)
    args.output.write_text(header)
