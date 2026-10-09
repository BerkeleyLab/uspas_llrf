import leep
import time


REG_RESET_LATCH = "arc_reset_latch"
REG_RESET_DEV = "arc_reset_arc_dev"
REG_TEST_MASK = "arc_test_mask"
REG_PERMIT_MASK = "arc_permit_mask"
REG_TEST_STB = "arc_test_stb"
REG_PERMITS = "arc_permit_raw"
NUM_CHAN = 3


def start_test(dev, test_chans=[]):
    testmask = 0
    if len(test_chans) == 0:
        print("WARNING: Testing zero channels.  Why would you do this?")
    for chan in test_chans:
        nchan = int(chan)
        assert ((nchan > 0) and (nchan <= NUM_CHAN)), \
               "Invalid channel number {}".format(nchan)
        testmask |= 1 << (chan - 1)
    dev.reg_write(((REG_TEST_MASK, testmask), (REG_TEST_STB, 1)))
    return


def get_permits(dev):
    return int(dev.reg_read((REG_PERMITS,))[0])


def do_test(args):
    chans = [int(x) for x in args.channels]
    print(f"Testing channels {chans}")
    dev = leep.open(args.dest)
    start_test(dev, chans)
    time.sleep(0.5)
    permits = get_permits(dev)
    print(f"Permits: {permits:03b}")
    return


def do_reset(args):
    print("Resetting")
    dev = leep.open(args.dest)
    dev.reg_write(((REG_RESET_DEV, 1),))
    time.sleep(0.5)
    permits = get_permits(dev)
    print(f"Permits: {permits:03b}")
    return


def do_permits(args):
    dev = leep.open(args.dest)
    permits = get_permits(dev)
    print(f"Permits: {permits:03b}")
    return


def do_collect_stats(args):
    dev = leep.open(args.dest)
    iters = args.iters
    if iters is not None:
        iters = int(iters)
    iters, errors = collect_stats(dev, iters)
    if errors == 0:
        print("PASS: {iters} Iterations")
    else:
        print(f"FAIL: {iters - errors}/{iters} = {100 * (iters - errors) / iters:.2f} % success")
    return


def expected_permits(testmask):
    if testmask == 1:
        return 2
    elif testmask == 2:
        return 1
    elif testmask == 3:
        return 0
    return 3


def collect_stats(dev, iterations=None):
    # None means run forever (until KeyboardInterrupt)
    iters = 0
    testmask = 1
    errors = 0
    # Reset
    dev.reg_write(((REG_RESET_DEV, 1),))
    time.sleep(0.6)
    while True:
        try:
            # Test each test channel
            dev.reg_write(((REG_TEST_MASK, testmask), (REG_TEST_STB, 1)))
            time.sleep(0.6)
            # Compare permit val to expected
            permits = get_permits(dev)
            expected = expected_permits(testmask)
            if permits != expected:
                print(f"{iters}: Test of mask {testmask:03b} failed (permits = {permits:03b} != {expected:03b})")
                errors += 1
            # Reset
            dev.reg_write(((REG_RESET_DEV, 1),))
            time.sleep(0.6)
            # Compare permit val to expected
            permits = get_permits(dev)
            if permits != 3:
                print(f"{iters}: Reset failed (permits = {permits})")
                errors += 1
            # repeat
            iters += 1
            if testmask == 3:
                testmask = 1
            else:
                testmask += 1
            if iterations is not None:
                if iters == iterations:
                    print("Done")
                    break
        except KeyboardInterrupt:
            print("Stopping")
            break
    return 2 * iters, errors


def main():
    import argparse
    parser = argparse.ArgumentParser("Arc Detector Interface Test")
    parser.add_argument("dest", help="LEEP destination (\"leep://$IP[:$PORT]\")")
    parser.set_defaults(action=lambda args: parser.print_help())
    subparsers = parser.add_subparsers(help="Command")
    parser_test = subparsers.add_parser("test")
    parser_test.set_defaults(action=do_test)
    parser_test.add_argument("channels", nargs="+", help="Channel(s) to test: 1, 2, 3")
    parser_reset = subparsers.add_parser("reset")
    parser_reset.set_defaults(action=do_reset)
    parser_permits = subparsers.add_parser("permits")
    parser_permits.set_defaults(action=do_permits)
    parser_stats = subparsers.add_parser("stats")
    parser_stats.set_defaults(action=do_collect_stats)
    parser_stats.add_argument("iters", nargs="?", default=None, help="Number of iterations to complete")
    args = parser.parse_args()
    return args.action(args)


if __name__ == "__main__":
    main()
