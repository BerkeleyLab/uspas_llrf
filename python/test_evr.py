import test
import time


def read_evr_regs(dev):
    time.sleep(2)
    read_list = ["evr_timestamp_valid", "gtx_rx_aligned", "evr_evcnt"]
    read_list += ["evr_live_ts_hi", "evr_live_ts_lo"]
    reg = dev.reg_read(read_list)
    if ((reg[0] != 1) and (reg[1] != 1)):
        raise ValueError("GTX not aligned and EVR timestamp is not valid")
    else:
        print("GTX aligned and EVR timestamps are valid")
    print(f"EVR event counter: {reg[2]}")
    print(f"EVR timestamp high 32-bits: {reg[3]:d}, low 32-bits: {reg[4]:d}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(
        description="Utility for testing phase ramping with\
                     leep register settings")
    parser.add_argument('-a', '--addr', default='192.168.19.122',
                        help='IP address')
    parser.add_argument('-p', '--port', type=int, default=803,
                        help='Port number')
    parser.add_argument('-t', '--timeout', type=float, default=0.1,
                        help='LEEP network timeout')

    args = parser.parse_args()
    leep_addr = "leep://" + str(args.addr) + str(":") + str(args.port)
    print(leep_addr)
    dev = test.open_leep(leep_addr, timeout=args.timeout, instance=[])
    read_evr_regs(dev)
