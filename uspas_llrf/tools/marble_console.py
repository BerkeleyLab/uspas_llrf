"""Post-boot check of the SoC firmware over the Marble's USB UART console.

Sends '?' and expects the console help, whose first line is
"GIT_REV_ID: <hex>". That needs a UART0 receive interrupt and the main loop,
so it fails when the firmware hangs after boot (which ping, gitid and
system_bist_pass, all set during boot, do not catch).

The UART's RTS line resets the SoC when released (UART_CTS edge in
top/common/marble_zest_mid.vh); opening the port asserts it, and hang-up on
close is turned off so closing the port does not release it.

    python -m uspas_llrf.tools.marble_console PORT [--git-id HEX]
"""
import argparse
import sys
import termios
import time

import serial


def open_console(port, baudrate=115200):
    ser = serial.Serial(port, baudrate=baudrate, timeout=0.1)
    attrs = termios.tcgetattr(ser.fd)
    attrs[2] &= ~termios.HUPCL  # keep RTS asserted on close
    termios.tcsetattr(ser.fd, termios.TCSANOW, attrs)
    return ser


def query_help(ser, timeout=3.0):
    """Send '?' and return the console's reply until it goes quiet."""
    ser.reset_input_buffer()
    ser.write(b'?')
    reply, t_end, t_quiet = b'', time.monotonic() + timeout, None
    while time.monotonic() < t_end:
        chunk = ser.read(256)
        if chunk:
            reply += chunk
            t_quiet = time.monotonic() + 0.3
        elif t_quiet is not None and time.monotonic() > t_quiet:
            break
    return reply.decode('utf-8', errors='replace')


def git_rev_id(reply):
    """The GIT_REV_ID value in the help reply, or None."""
    for line in reply.splitlines():
        if line.startswith('GIT_REV_ID:'):
            try:
                return int(line.split(':', 1)[1].strip(), 16)
            except ValueError:
                return None
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('port', help='console tty, e.g. /dev/serial/by-id/usb-LBNL_Marble_000037-if02-port0')
    parser.add_argument('--git-id', help='expected GIT_REV_ID (hex, e.g. the short commit id)')
    parser.add_argument('--baudrate', type=int, default=115200)
    parser.add_argument('--timeout', type=float, default=3.0)
    args = parser.parse_args()

    with open_console(args.port, args.baudrate) as ser:
        reply = query_help(ser, args.timeout)
    rev = git_rev_id(reply)
    if rev is None:
        print(f"FAIL: no console help from {args.port}; received {reply!r}")
        sys.exit(1)
    if args.git_id is not None and rev != int(args.git_id, 16):
        print(f"FAIL: GIT_REV_ID {rev:08x}, expected {args.git_id}")
        sys.exit(1)
    print(f"console OK, GIT_REV_ID {rev:08x}")


if __name__ == '__main__':
    main()
