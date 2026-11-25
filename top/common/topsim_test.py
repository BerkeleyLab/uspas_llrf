#!/usr/bin/env python3
"""Headless test of the simulated top (make topsim_test in top/<design>/).

Runs Vmarble_zest_frame (make topsim) with its UDP bridge (udp_tap.c), so
LEEP reaches the simulated board on localhost, and follows the SoC's console
(the simulated UART, on the simulation's stdout). The firmware is its
SIMULATION build (TOPSIM_FW=sim): it reads the XADC model, initializes the
shell and writes system_bist_pass, without the Marble's I2C devices or the
Zest, which topsim does not model. Checks, all through the top's decode:

  - the config ROM (read by LEEPDevice) holds the merged register map, and
    git_rev_id reads the build's ID;
  - every register of each block reads (scalars, and one word of each
    array), and the BSP's GT reference clock counter reads 2**16 (topsim
    runs that clock and the localbus clock from one clock);
  - the firmware passes its self-test (the XADC, and the LLRF init registers
    written and read back by the CPU) and sets system_bist_pass;
  - the shell holds the init values: what the CPU wrote through its address
    header (llrf_regs_addr.h) reads back over Ethernet through the ROM's map;
  - distinct values written to every rw register (8 bits or more) of all
    blocks read back: no two registers share an address.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import threading
import time

from leep.raw import LEEPDevice

TOP_JSON = 'marble_zest_top'
# the BSP's GT reference clock counter, against the localbus clock
BSP_FREQ = ('gt_refclk_frequency', 1 << 16)
# init registers the firmware changes after it checks them (init_llrf():
# circle_buf_flip, and align_mo_phase() sets rx_dds_phase_shift)
INIT_CHANGED = {'circle_buf_flip', 'rx_dds_phase_shift'}
# rw registers that do not read back what was written
NO_READBACK = set()


def mask(value, info):
    """value in the register's width (LEEP sign-extends signed registers)"""
    return int(value) & ((1 << info['data_width']) - 1)


class Sim:
    """The simulation process and its console lines."""

    def __init__(self, cmd, port, log):
        env = dict(os.environ, TOPSIM_UDP_PORT=str(port))
        self.proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                     env=env, text=True, errors='replace')
        self.lines = []
        self.cond = threading.Condition()
        self.log = open(log, 'w') if log else None
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in self.proc.stdout:
            if self.log:
                self.log.write(line)
                self.log.flush()
            with self.cond:
                self.lines.append(line.rstrip('\n'))
                self.cond.notify_all()
        with self.cond:
            self.cond.notify_all()

    def wait_for(self, pattern, timeout):
        """The first match of pattern in the console, waiting up to timeout s."""
        rx = re.compile(pattern)
        t_end = time.monotonic() + timeout
        seen = 0
        with self.cond:
            while True:
                for line in self.lines[seen:]:
                    m = rx.search(line)
                    if m:
                        return m
                seen = len(self.lines)
                left = t_end - time.monotonic()
                if self.proc.poll() is not None:
                    raise RuntimeError(f'simulation exited ({self.proc.returncode}) before /{pattern}/')
                if left <= 0:
                    raise TimeoutError(f'no /{pattern}/ in the console after {timeout} s')
                self.cond.wait(min(left, 1.0))

    def stop(self):
        self.proc.terminate()
        try:
            self.proc.wait(10)
        except subprocess.TimeoutExpired:
            self.proc.kill()


def load(fn):
    with open(fn) as f:
        return json.load(f)


def base(v):
    b = v['base_addr']
    return int(b, 0) if isinstance(b, str) else b


class Checks:
    def __init__(self):
        self.failed = 0

    def __call__(self, ok, what):
        print(('PASS ' if ok else 'FAIL ') + what, flush=True)
        self.failed += not ok


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--sim', default='./Vmarble_zest_frame')
    ap.add_argument('--port', type=int, default=8030, help='localhost UDP port for LEEP')
    ap.add_argument('-m', '--merged', required=True, help='merged register map (marble_zest.json)')
    ap.add_argument('-j', '--json', nargs='+', required=True, help='block JSONs, named after their modules')
    ap.add_argument('--init-regs', required=True, help='llrf_shell_init_regs.json')
    ap.add_argument('--git-id', type=lambda x: int(x, 16), default=0xdeadf00d,
                    help="git_rev_id (hex); topsim builds with marble_zest_mid.vh's default")
    ap.add_argument('--boot-timeout', type=float, default=600, help='wall-clock seconds for the firmware')
    ap.add_argument('--log', default='topsim_console.log', help='copy of the console')
    args = ap.parse_args()

    check = Checks()
    merged = load(args.merged)
    blocks = {os.path.splitext(os.path.basename(f))[0]: load(f) for f in args.json}
    blocks.pop(TOP_JSON, None)
    sim = Sim([args.sim], args.port, args.log)
    try:
        sim.wait_for(r'^udp_tap:', 60)
        dev = LEEPDevice(f'127.0.0.1:{args.port}', timeout=5)

        # the config ROM, and the git ID overlay
        rom = {k: base(v) for k, v in (dev.regmap or {}).items() if k != '__metadata__'}
        want = {k: base(v) for k, v in merged.items()}
        check(rom == want, f'config ROM: {len(rom)} registers, as in {args.merged}')
        git_id = int(dev.reg_read(['git_rev_id'])[0])
        check(git_id == args.git_id, f'git_rev_id {git_id:#x} (expect {args.git_id:#x})')

        # every register of each block (one word of each array)
        for blk, regs in blocks.items():
            names = sorted(regs)
            vals = dict(zip(names, dev.reg_read_size([(n, 1) for n in names])))
            check(len(vals) == len(names), f'{blk}: {len(names)} registers read')

        # the firmware: XADC, LLRF init (writes and reads back the init
        # registers through the CPU's address header), system_bist_pass
        t0 = time.monotonic()
        verdict = sim.wait_for(r'^(PASS|FAIL)$', args.boot_timeout).group(1)
        print(f'firmware: {verdict} after {time.monotonic() - t0:.0f} s', flush=True)
        check(verdict == 'PASS', 'firmware self-test (XADC, LLRF init)')
        bist = None
        for _ in range(50):  # written right after the verdict
            bist = int(dev.reg_read(['system_bist_pass'])[0])
            if bist:
                break
            time.sleep(0.1)
        check(bist == 1, f'system_bist_pass {bist}')

        # the BSP's clock counter (its first gate period has passed by now)
        name, want = BSP_FREQ
        f = int(dev.reg_read([name])[0])
        check(abs(f - want) <= 1, f'marble_bsp: {name} {f} (expect {want})')

        # what the CPU wrote, read over Ethernet: the two address paths agree
        init = load(args.init_regs)
        names = sorted(n for n in init if n not in INIT_CHANGED)
        got = {n: mask(x, merged[n]) for n, x in zip(names, dev.reg_read(names))}
        bad = [f'{n} {got[n]:#x} (init {mask(init[n], merged[n]):#x})' for n in names
               if got[n] != mask(init[n], merged[n])]
        check(not bad, f'llrf_shell: {len(names)} registers hold the firmware init values'
              + (': ' + ', '.join(bad) if bad else ''))

        # a pattern in every rw register of 8 bits or more, all blocks at
        # once, read back: no two of them share an address
        rw = sorted(n for regs in blocks.values() for n, v in regs.items()
                    if v['access'] == 'rw' and v.get('addr_width', 0) == 0 and v['data_width'] >= 8
                    and n not in NO_READBACK)
        pattern = {n: mask(0x5a5a5a5a ^ (0x01010101 * i), merged[n]) for i, n in enumerate(rw)}
        dev.reg_write(list(pattern.items()))
        got = {n: mask(x, merged[n]) for n, x in zip(rw, dev.reg_read(rw))}
        bad = [f'{n} {got[n]:#x} (wrote {pattern[n]:#x})' for n in rw if got[n] != pattern[n]]
        check(not bad, f'{len(rw)} rw registers read back distinct patterns'
              + (': ' + ', '.join(bad) if bad else ''))
    except (RuntimeError, TimeoutError, OSError) as e:
        check(False, str(e))
    finally:
        sim.stop()
    print(f'{check.failed} check(s) failed' if check.failed else 'all checks passed')
    sys.exit(1 if check.failed else 0)


if __name__ == '__main__':
    main()
