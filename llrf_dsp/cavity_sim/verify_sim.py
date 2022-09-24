#!/usr/bin/python3
import numpy as np
from matplotlib.pyplot import *
from scipy import stats

CORDIC_GAIN    = 1.64676
LO_AMP         = 74840                    # < 2^17 / 1.64676
RX_AMP_GAIN    = 2.9337 * CORDIC_GAIN     # Measured
RX_PHS_GAIN    = 0                        # Measured, deg
OPEN_AMP_GAIN  = (1 << 19) / (CORDIC_GAIN * LO_AMP * CORDIC_GAIN)
OPEN_PHS_GAIN  = 0       # Measured, deg

def verify(setp, meas, name):
    print("Verifying", name)
    slope, intercept, r_value, p_value, std_err = stats.linregress(setp, meas)
    print("r_value:  %12f  " % (r_value), end="")
    if (r_value >= 0.99):
        print("PASS")
    else:
        print("FAIL")

    print("slope:    %12f  " % (slope), end="")
    if (slope >= 0.99 and slope <= 1.1):
        print("PASS")
    else:
        print("FAIL")

    print("offset:   %12f  " % (intercept), end="")
    if (intercept >= -100 and slope <= 100):
        print("PASS")
    else:
        print("FAIL")

    plot(setp, meas,  "o", label="measured_"+name)
    plot(setp, intercept + slope*setp, 'r', label='Fit r=%.2f, m=%.4f, offset=%.2f' % (r_value, slope, intercept))
    xlabel("Setpoint (In)")
    ylabel("Raw Value (Out)")
    title("PI Loop: Measured vs. Setpoint for " + name)
    legend()
    grid(True)


def plot_and_verify(phs_sweep_fname, amp_sweep_fname, name, xoffset):
    print("*** " + name + " ***")

    # Phase Check
    data = np.loadtxt(phs_sweep_fname)
    #phs_setpoint  = (data[xoffset:, 2] * 360.0)  / 2**18 - OPEN_PHS_GAIN
    #measured_phs  = (data[xoffset:, 3] * 360.0)  / 2**18 - RX_PHS_GAIN
    phs_setpoint  = data[xoffset:, 2]
    measured_phs  = data[xoffset:, 3]
    figure(1)
    suptitle(name)
    subplot(211)
    verify(phs_setpoint, measured_phs, "phs")

    # Amp Check
    data = np.loadtxt(amp_sweep_fname)
    #amp_setpoint  = data[xoffset:, 4] / OPEN_AMP_GAIN
    #measured_amp  = data[xoffset:, 5] / RX_AMP_GAIN
    amp_setpoint  = data[xoffset:, 4]
    measured_amp  = data[xoffset:, 5]
    subplot(212)
    verify(amp_setpoint, measured_amp, "amp")
    tight_layout()
    show()

plot_and_verify("./dsp_core_sweep_phs_open.dat", "./dsp_core_sweep_amp_open.dat", "Open Loop", 100)
plot_and_verify("./dsp_core_sweep_phs_closed.dat", "./dsp_core_sweep_amp_closed.dat", "Closed Loop", 500)
