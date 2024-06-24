from llrf_app.app import LLRFApp
from llrf_app.leep.cli import getargs
import logging
logger = logging.getLogger(__name__)


def open_leep(addr, **kwargs):
    if addr.startswith('leep://'):
        return LLRFApp(addr[7:], **kwargs)
    else:
        raise ValueError("Unknown '%s' must begin with leep://" % addr)


if __name__ == "__main__":
    args = getargs()
    logging.basicConfig(level=args.debug)
    dev = open_leep(args.dest, timeout=args.timeout, instance=args.inst)
    args.func(args, dev)
