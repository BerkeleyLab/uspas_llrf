import time
from pymodbus.exceptions import ModbusIOException
from pymodbus.pdu.pdu import ExceptionResponse
from modbus_test import getClient, get_exception_str


def _int(x):
    try:
        return int(x)
    except ValueError:
        pass
    try:
        return int(x, 16)
    except ValueError:
        pass
    return int(x, 2)


def _get_uptime(start, now):
    dts = now - start
    days = 0
    hrs = 0
    mins = 0
    if dts > 24 * 60 * 60:
        days = int(dts // (24 * 60 * 60))
    if dts > 60 * 60:
        hrs = int(dts // (60 * 60) - days * 24)
    if dts > 60:
        mins = int(dts // 60 - (days * 24 * 60) - (hrs * 60))
    secs = int((dts - (days * 24 * 60 * 60) - (hrs * 60 * 60) - (mins * 60)))
    return days, hrs, mins, secs


def get_uptime(start, now):
    days, hrs, mins, secs = _get_uptime(start, now)
    ll = []
    if days > 0:
        ll.append(f"{days} days")
    if hrs > 0 or days > 0:
        ll.append(f"{hrs} hrs")
    if mins > 0 or hrs > 0 or days > 0:
        ll.append(f"{mins} mins")
    ll.append(f"{secs} secs")
    return ", ".join(ll)


def test_get_uptime():
    import math
    for n in (1.0e3, 1.0e4, 1.0e5, 1.0e6):
        days, hrs, mins, secs = _get_uptime(0, n)
        us = get_uptime(0, n)
        print(f"{n}: {us}")
        total = 24 * 60 * 60 * days + 60 * 60 * hrs + 60 * mins + secs
        if not math.isclose(total, n):
            print(f"FAIL! {total} != {n}")
    return


def doStressTest(mb_client, addr=0, polling_period_ms=100, error_limit=10):
    polling_period_ms = float(polling_period_ms)
    addr = _int(addr)
    error_limit = _int(error_limit)
    response_errors = 0
    successful_messages = 0
    long_responses = 0
    print(f"Polling device at {mb_client}")
    print("{:<18s}{:<12s}{:<24s}{:<24s}".format("Transactions", "Errors", "Long Response Times", "Uptime"))
    print("".join(['-'] * (18 + 12 + 24 + 24)))
    upstart = time.time()
    last_update = upstart
    while True:
        try:
            start = time.time()
            val = mb_client.read_holding_registers(addr, count=1)  # function code 3
            end = time.time()
            interval_ms = 1.0e3 * (end - start)
            if interval_ms > polling_period_ms:
                long_responses += 1
            if isinstance(val, ExceptionResponse):
                print(f"  ERROR: val.exception_code = {get_exception_str(val.exception_code)} ({val.exception_code})")
                response_errors += 1
            else:
                successful_messages += 1
            now = time.time()
            if now - last_update > 1.0:
                last_update = now
                uptime_str = get_uptime(upstart, now)
                print("\r{:<18s}{:<12s}{:<24s}{:<24s}".format(str(successful_messages),
                                                              str(response_errors),
                                                              str(long_responses), uptime_str), end="")
            sleep_time = max(0, polling_period_ms - (1.0e3 * (time.time() - start)))
            time.sleep(sleep_time * 1.0e-3)
            if response_errors >= error_limit:
                print("\n::: Hit error limit")
                break
        except (KeyboardInterrupt, ModbusIOException) as err:
            if isinstance(err, ModbusIOException):
                print(err)
            else:
                print("\nClosing")
            break
    # print stats
    return 0


def main():
    import argparse
    parser = argparse.ArgumentParser("Modbus comms durability test")
    parser.add_argument("-m", "--modbus_adapter", default=None)
    parser.add_argument("-p", "--poll_period_ms", default=100, help="Modbus polling period in milliseconds.")
    parser.add_argument("-a", "--address", default=30, help="Modbus register address to poll.")
    parser.add_argument("-e", "--error_limit", default=10, help="Number of errors to permit before closing.")
    args = parser.parse_args()
    mb_client = getClient(args.modbus_adapter)
    return doStressTest(mb_client, args.address, args.poll_period_ms)


if __name__ == "__main__":
    exit(main())
