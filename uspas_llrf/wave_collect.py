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
from uspas_llrf.model.slow_bridge import decode_slow_data


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
    """Decode slow data words that start at cbuf_stat1 (dsp_slow_data[17:])
    with uspas_llrf.model.slow_bridge.decode_slow_data. Returns
    (cbuf_stat1, cbuf_stat2, cbuf_count, tag, tag_old, mins, maxs,
     pulse_id, ticks, fw_ts): pulse_id and ticks are the EVR timestamp's
    seconds (360 Hz pulse ID) and ticks, fw_ts the first word of the FPGA
    cycle counter.
    """
    sd = decode_slow_data(slw_d, offset=0)
    return (
        sd.cbuf_stat1, sd.cbuf_stat2, sd.cbuf_count, sd.tag, sd.tag_old,
        [int(v) for v in sd.adc_min], [int(v) for v in sd.adc_max],
        sd.evr_seconds, sd.evr_ticks, int(sd.raw[25])
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
