"""LEMP Chassis Data Acquisition Tool

Inspired by sel_waves.py, res_waves.py and res_data_acq.py from LCLS-II repo

This script facilitates the passive acquisition of LEMP RF and
wideband waveforms.

The following type of data can be collected:

    ADC raw waveforms
    I&Q waveforms (individual channels and all channels)
    cic buffer waveforms

Typical usage examples:

    python3 wave_collect.py -a leep://192.168.19.171:803
"""

import numpy
from datetime import datetime
import leep


def wave_collect_run(dev, count, filewritepath=None):
    for run_n in range(count):
        (iq_data, datetimestr, slow_data) = wave_collect(dev)
        isd = interpret_slow_data(slow_data)

        print(f"Acquired {run_n + 1} / {count} buffers. {datetimestr}. "
              f"Pulseid {isd[7]}. Buffer counter {isd[2]}. "
              f"Ticks {isd[8]}")

        # circle_count, pulseid
        header = datetimestr + " %d %d" % (isd[2], isd[7])

        if filewritepath:
            # Make sure path has terminating '/'
            if filewritepath.endswith('/') is False:
                filewritepath = filewritepath + '/'
        else:
            filewritepath = ''

        wname = filewritepath + 'lemp_iq_%3.3d' % (run_n)
        numpy.savetxt(wname, numpy.asarray(iq_data),
                      fmt="%10.7f", header=header)


def interpret_slow_data(slw_d):
    # cbuf_stat1, cbuf_stat2, cbuf_count, tag, tag_old,
    # adc0_min, adc1_min, ..., adc6_min, adc7_min,
    # adc0_max, adc1_max, ..., adc6_max, adc7_max,
    # evr_seconds (pulse_id), evr_evticks, timestamp

    cbuf_stat1 = slw_d[0]
    cbuf_stat2 = slw_d[1]
    cbuf_count = slw_d[2]
    tag = slw_d[3]
    tag_old = slw_d[4]

    mins = [int(slw_d[m]) - 65536 if slw_d[m] > 32767 else int(slw_d[m])
            for m in range(5, 13)]
    maxs = [int(slw_d[m]) - 65536 if slw_d[m] > 32767 else int(slw_d[m])
            for m in range(13, 21)]

    # Pulse_id at 360 Hz. Only uses 17 bits. That's about 6 mins. Why?
    pulse_id = slw_d[21] * (2 ** 16) + slw_d[22]

    # Counter at dsp clk (119MHz). Resets with pulseid
    ticks = slw_d[23] * (2 ** 16) + slw_d[24]

    # FPGA internal Timestamp
    fw_ts = slw_d[25]

    return (
        cbuf_stat1, cbuf_stat2, cbuf_count, tag, tag_old,
        mins, maxs, pulse_id, ticks, fw_ts
    )


def wave_collect(dev):
    tag_match, slow_data, time_now = wait_for_acq(dev)
    datetimestr = time_now.isoformat() + "Z"
    iq_data, = dev.reg_read(['iq_buf'])

    # First 17 bytes of slow_data are padding
    # iq_data is 20 * 1024 = 20480
    return (iq_data[0:20480], datetimestr, slow_data[17:])


def wait_for_acq(dev, tag=False, timeout=5.0):
    start = datetime.utcnow()
    T, = dev.reg_read(['dsp_tag'])

    while True:
        dev.reg_write([('sig_buf_flip', 1)], instance=[])

        while True:
            now = datetime.utcnow()
            delta = now - start
            delta_us = delta.seconds + delta.microseconds / 1e6
            if delta_us >= timeout:
                raise RuntimeError('Timeout')

                ''' TODO:
                    use exchange() and optimize to fetch slow_data[33] as well
                '''
            ready_iq, = dev.reg_read(['sig_iq_buf_ready'])
            mask = 0xfffff
            if (ready_iq & mask) == mask:
                break

        slow, = dev.reg_read(['dsp_slow_data'])
        tag_old = slow[20]
        tag_new = slow[21]
        dT = (tag_old - T) & 0xff
        tag_match = dT == 0 and tag_new == tag_old

        if not tag:
            break
        if tag_match:
            # all done, waveform reflects latest parameter changes
            break

        if dT != 0xff:
            msg = 'acquisition collides with another client:'
            msg += '%d %d %d' % (tag_old, tag_new, T)
            raise RuntimeError(msg)

    return tag_match, slow, now


def wave_collect_cli(ap):
    ap.add_argument('-a', '--address', dest="dev_addr", required=True,
                    help="Device address")
    ap.add_argument('-c', '--count', dest="count", type=int,
                    help="Number of waveform acquisitions", default=1)
    ap.add_argument('-w', '--filewritepath', dest='filewritepath',
                    default=None, help='Output file path'),


if __name__ == "__main__":

    from argparse import ArgumentParser

    parser = ArgumentParser(description="LEMP Chassis Data Acquisition Tool.")
    wave_collect_cli(parser)
    args = parser.parse_args()

    # Validate inputs
    if args.count < 1:
        print("ERROR: Invalid count")
        exit(-1)

    print('Collect waves')
    print('Carrier board URL %s' % args.dev_addr)
    dev = leep.open(args.dev_addr)

    wave_collect_run(dev, args.count, args.filewritepath)
