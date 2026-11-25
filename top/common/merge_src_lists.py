#!/usr/bin/env python3
"""Merge source lists (.f) into one, without duplicates.

Each block's make writes <block>.f: `+incdir+<dir>` lines, then source files,
absolute paths. The blocks share bedrock modules, and some generate the same
file in their own directory (cordicg_b22.v), so a file is dropped when the
same path is already listed, or a file with the same name and the same
content. Two different files with the same name are an error: they would be
two versions of one module.
"""
import argparse
import filecmp
import os
import sys


def merge(lines):
    out, by_name = [], {}
    for line in lines:
        line = line.strip()
        if not line or line in out:
            continue
        if not line.startswith('+'):
            name = os.path.basename(line)
            first = by_name.setdefault(name, line)
            if first != line:
                if filecmp.cmp(first, line, shallow=False):
                    continue
                sys.exit(f"{name}: {first} and {line} differ")
        out.append(line)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('-o', '--output', required=True)
    ap.add_argument('--incdir', nargs='*', default=[], help='include directories, first')
    ap.add_argument('--src', nargs='*', default=[], help='sources, before the lists')
    ap.add_argument('lists', nargs='*', help='block source lists (.f)')
    args = ap.parse_args()
    lines = [f'+incdir+{os.path.abspath(d)}' for d in args.incdir]
    lines += [os.path.abspath(f) for f in args.src]
    for fn in args.lists:
        with open(fn) as f:
            lines += f.read().splitlines()
    with open(args.output, 'w') as f:
        f.write('\n'.join(merge(lines)) + '\n')


if __name__ == '__main__':
    main()
