import argparse
import numpy as np
from matplotlib import pyplot as plt
from llrf_app.app import LLRFApp
from llrf_app.leep.cli import readwrite, listreg, dumpjson
import logging
logger = logging.getLogger(__name__)


def waveform(args, dev):
    if args.plot:
        dev.plot_cbuf_wfm()
        plt.show()
    else:
        logger.info("waveforms:")
        dat = dev.read_cbuf_data()
        print(dat.shape)
        print(dat.reshape(-1, dev.n_chan).T)


def open_leep(addr, **kwargs):
    if addr.startswith('leep://'):
        return LLRFApp(addr[7:], **kwargs)
    else:
        raise ValueError("Unknown '%s' must begin with leep://" % addr)


def getargs():
    p = argparse.ArgumentParser()
    p.add_argument(
        '-v', '--verbose', action='store_const',
        const=logging.DEBUG, default=logging.INFO)
    p.add_argument(
        '-q', '--quiet', action='store_const',
        const=logging.WARN, dest='verbose')
    p.add_argument('-t', '--timeout', type=float, default=5.0)
    p.add_argument('-i', '--inst', action='append', default=[])
    p.add_argument(
        '-d', '--dest', metavar="URI",
        default="leep://192.168.19.122:803")

    sp = p.add_subparsers()

    s = sp.add_parser('reg', help='read/write registers')
    s.set_defaults(func=readwrite)
    s.add_argument('reg', nargs='+', help="register[=newvalue]")

    s = sp.add_parser('list', help='list registers')
    s.set_defaults(func=listreg)

    s = sp.add_parser('json', help='print json')
    s.set_defaults(func=dumpjson)

    s = sp.add_parser('waveform', help='cbuf waveform acquisition.')
    s.set_defaults(func=waveform)
    s.add_argument('-p', '--plot', action='store_true', default=False,
                   help='Plot acquired data with matplotlib')

    return p.parse_args()


if __name__ == "__main__":
    args = getargs()
    logging.basicConfig(level=args.verbose)
    dev = open_leep(args.dest, timeout=args.timeout, instance=args.inst)
    args.func(args, dev)
