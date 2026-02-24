import numpy as np
from scipy import signal
import matplotlib.pyplot as plt
import json
from pathlib import Path


with open(Path(__file__).parent.joinpath('settings.json')) as f:
    settings = json.load(f)

dsp_config = settings['dsp_config']
cav_config = settings['cav_config']


def wrap_phase(phs: float, deg=True):
    """Wrap phase value to be within [-180, 180] or [-pi, pi].
    """
    scale = 180 if deg else np.pi
    return (phs + scale) % (2 * scale) - scale


def clip_int(value, n_bit=16):
    max_value = (1 << n_bit - 1) - 1
    min_value = -(1 << n_bit - 1)
    return max(min_value, min(int(value), max_value))


def to_signed(value: int, width: int = 18):
    """Converts an integer to the signed value from two's compliment format
        e.g. 0b1000 is -8
    """
    v = int(value)
    if v >= 2**(width - 1):
        return v - 2**width
    else:
        return v


def calc_ps(wfm, title='', fullscale=32767, fs_mhz=115):
    """Calculate power spectrum of a waveform"""
    fsdb = 20 * np.log10(fullscale / np.sqrt(2))
    f, pxx = signal.periodogram(
        wfm, fs_mhz, 'flattop', scaling='spectrum', nfft=8192)
    psd_dbfs = 10 * np.log10(pxx) - fsdb
    return f, psd_dbfs


def plot_ps(f, psd_dbfs, title='', annotate=False):
    """Plot power spectrum of a waveform"""
    fig, ax = plt.subplots()
    ax.set_xlabel('Freq [MHz]')
    ax.set_ylabel('Mag [dBFS]')
    ax.set_ylim(-120, 10)
    ax.set_title(title)
    if len(psd_dbfs.shape) == 1:
        ax.plot(f, psd_dbfs)
        if annotate:
            idx = np.argmax(psd_dbfs)
            pwr = psd_dbfs[idx]
            ax.annotate(
                f'{f[idx]:5.3f}  MHz\n {pwr:5.3f} dBFS',
                xy=(f[idx], pwr), xytext=(1, -20),
                arrowprops=dict(shrink=0.05))
    elif len(psd_dbfs.shape) == 2:   # plot psd array
        for ix, p in enumerate(psd_dbfs):
            ax.plot(f, p, label='adc' + str(ix))
        ax.legend()
