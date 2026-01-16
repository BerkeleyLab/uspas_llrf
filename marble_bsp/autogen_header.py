"""Generate C header from newad JSON register map."""
import json
import argparse


# Registers that need LB_ prefix for backward compatibility
LB_PREFIX_REGS = {'bsp_info_buf', 'marble_mbox_buf'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('-i', '--input', required=True, help='Input JSON file')
    parser.add_argument('-o', '--output', required=True, help='Output C header file')
    args = parser.parse_args()

    with open(args.input, 'r') as f:
        regs = json.load(f)

    guard = args.output.split('/')[-1].upper().replace('.', '_')
    with open(args.output, 'w') as f:
        f.write(f"// Auto-generated from {args.input}\n")
        f.write(f"#ifndef _{guard}_\n")
        f.write(f"#define _{guard}_\n\n")
        for name, info in sorted(regs.items(), key=lambda x: x[1]['base_addr']):
            addr = info['base_addr']
            width = info.get('data_width', 32)
            access = info.get('access', 'rw')
            prefix = 'LB_' if name in LB_PREFIX_REGS else ''
            name_upper = (prefix + name).upper()
            f.write(f"#define {name_upper:40s} 0x{addr:05x}  // {access}, {width}-bit\n")
        f.write(f"\n#endif // _{guard}_\n")


if __name__ == '__main__':
    main()
