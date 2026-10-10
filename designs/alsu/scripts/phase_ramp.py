import sys
import time
import math
sys.path.append("../submodules/feed/src/python")


def close_loop(addr, Kp_amp, Ki_amp, Kp_phs, Ki_phs, amp_setp, phs_setp):
    # set Kp and Ki values for both amp and phase loops
    cgain = 2.58330
    amp_setp = amp_setp / cgain
    addr.reg_write([("Kp_amp", Kp_amp), ("Ki_amp", Ki_amp),
                    ("Kp_phs", Kp_phs),
                    ("Ki_phs", Ki_phs), ("amp_setpoint", amp_setp),
                    ("phs_setpoint", phs_setp)])
    addr.reg_write([("phs_loop_enable", 0), ("amp_loop_enable", 0)])
    addr.reg_write([("wave_trig_sel", 5)])


def ramp_settings(addr, rate, steps, totaltime, errthres):
    PT = 1.0 / 8.7206e-9
    ramp_time = math.ceil((totaltime / steps) * PT)
    addr.reg_write([("phase_ramp_rate", rate),
                    ("phase_ramp_steps", steps),
                    ("phase_ramp_ttime", ramp_time),
                    ("phase_ramp_error_threshold", errthres)])


def f_print(val, label="", ref=None, nom=None):
    f = val * ref * 0.5**16
    suf = ""
    if nom is not None:
        ppm = (f / nom - 1) * 1e6
        suf = ", %.1f ppm off nominal." % ppm
        if abs(ppm) > 100:
            suf += "  BAD!"
    print("%s: %10.6f MHz%s" % (label, f, suf))


def start_ramp(addr, rate, steps, totaltime, phs_setp, errthres, verbose):
    stati = addr.reg_read(['gtx_rx_clk_frequency'])[0]
    f_print(stati, label="EVR clk freq", ref=125.0, nom=125.1)
    time.sleep(1)
    # convert degree to register values
    d2b = (2**18) / 360
    d2b_e = (2**16) / 360
    irate = rate * d2b
    iphs_setp = phs_setp * d2b
    ierrthres = errthres * d2b_e
    close_loop(addr, 100, 10, 100, 10, 8000, iphs_setp)
    ramp_settings(addr, irate, steps, totaltime, ierrthres)
    addr.reg_write([("amp_loop_reset", 1), ("phs_loop_reset", 1)])
    time.sleep(1)
    addr.reg_write([("phs_loop_enable", 1), ("amp_loop_enable", 1)])
    time.sleep(1)
    addr.reg_write([("amp_loop_reset", 0), ("phs_loop_reset", 0)])
    time.sleep(1)
    addr.reg_write([("phase_ramp_enable", 1)])
    loop_error = addr.reg_read([("loop_phs_err")])[0]
    if loop_error > 2000:
        addr.reg_write([("phase_ramp_enable", 0)])
        raise Exception("ERROR: Phase loop error higher than the threshold.")

    time.sleep(1)
    flip = 0 if rate < 0 else -1
    expected_setpoint = phs_setp + (rate * steps) + flip
    # if expected_setpoint > 180.0:  # Wrap phase
    #     expected_setpoint -= 360.0
    # elif expected_setpoint < -180.0:
    #     expected_setpoint += 360.0

    time.sleep(1)
    ramp_finish = addr.reg_read([("ramp_finish")])[0]
    if verbose:
        read_list = ["Kp_amp", "Ki_amp", "Kp_phs",
                     "Ki_phs", "amp_setpoint",
                     "phs_setpoint", "phs_loop_enable", "amp_loop_enable",
                     "amp_loop_reset", "phs_loop_reset", "phase_ramp_enable",
                     "phase_ramp_error_threshold",
                     "phase_ramp_rate", "phase_ramp_steps",
                     "phase_ramp_ttime",
                     "phase_ramp_setpoint", "phase_ramp_finish", "phase_ramp_timeout"]
        ans_list = addr.reg_read(read_list)
        for p, a in zip(read_list, ans_list):
            print("%s: %d" % (p, a))

    if ramp_finish == 1:
        print("Ramping done!!")
        final_setpoint = (math.floor((addr.reg_read([("phase_ramp_setpoint")])[0]) * (360 / (2**18))))
        print("Expected setpoint: %d deg" % (expected_setpoint))
        print("Final setpoint: %d deg" % (final_setpoint))
        if (int(expected_setpoint) == int(final_setpoint)):
            print("Expected and measured setpoints match!")
        else:
            addr.reg_write([("phase_ramp_enable", 0)])
            raise Exception("ERROR: Expected and measured don't\
                            setpoint match!")
    else:
        addr.reg_write([("phase_ramp_enable", 0)])
        raise ValueError("Ramp finish never went high")
    addr.reg_write([("phase_ramp_enable", 0)])


if __name__ == "__main__":
    import argparse
    import leep
    parser = argparse.ArgumentParser(
        description="Utility for testing phase ramping with\
                     leep register settings")
    parser.add_argument('-a', '--addr', default='192.168.19.122',
                        help='IP address')
    parser.add_argument('-p', '--port', type=int, default=803,
                        help='Port number')
    parser.add_argument('-r', '--rate', type=int, default=1, help='Step size')
    parser.add_argument('-s', '--steps', type=int, default=10,
                        help='Total number of steps to take')
    parser.add_argument('-t', '--ttime', type=float, default=100e-3,
                        help='Total ramp period in seconds')
    parser.add_argument('-i', '--phs_setp', type=int, default=10,
                        help='Initial phase setpoint in degree')
    parser.add_argument('-e', '--err_thres', type=int, default=10,
                        help='Phase loop error threshold in degree')
    parser.add_argument('-v', '--verbose', action='store_true',
                        help='Verbose output')

    args = parser.parse_args()
    leep_addr = "leep://" + str(args.addr) + str(":") + str(args.port)
    print(leep_addr)
    dev = leep.open(leep_addr, instance=[])
    start_ramp(dev, args.rate, args.steps, args.ttime, args.phs_setp,
               args.err_thres, args.verbose)
