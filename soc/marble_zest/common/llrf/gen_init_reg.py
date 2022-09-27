#!/usr/bin/env python
from datetime import datetime
import json
import os
import argparse


def write_init(init_dict, ifname, ofname):
    cf = """
    // Automatically generated register map of the local bus
    // Source:    {0}
    // Generated: {1}

    """.format(os.path.abspath(ifname), datetime.now().strftime("%D, %T"))

    var_name = os.path.basename(ifname).split('.')[0]
    dsp_name = var_name.split('_')[0]
    cf = '#include "' + dsp_name + '.h"\n'
    cf += '#include "' + dsp_name + '_regs_addr.h"\n'
    cf += 't_lbreg32 ' + var_name + '[] = {\n'

    for k in sorted(init_dict.keys()):
        cf += "   {{{0:36s} {1:8d}}},\n".format(
                k.upper() + ',',
                init_dict[k]
                # np.bitwise_and(init_dict[k], 0xffffffff)
                )
    cf += '};\n'
    cf += 'const t_init_llrf_data llrf_init_data = {'

    cf += '''
    sizeof({}) / sizeof({}[0]),
    {}\n'''.format(var_name, var_name, var_name)

    cf += '};\n'
    with open(ofname, "w") as f:
        f.write(cf)
    print('Written: {} regs.'.format(len(init_dict)))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('-i', '--input', default='init_reg.json')
    parser.add_argument('-o', '--output', default='init_reg.c')

    args = parser.parse_args()
    init_fname = args.input
    dest_fname = args.output

    with open(init_fname) as f:
        init_dict = json.load(f)
        write_init(init_dict, init_fname, dest_fname)
