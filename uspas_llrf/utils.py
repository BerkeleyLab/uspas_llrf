import numpy as np
from scipy import signal
import matplotlib.pyplot as plt
import json
from pathlib import Path
from scipy.optimize import curve_fit


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


def fit_sine(y_data, initial_guess, verbose=False):
    x_data = np.arange(0, len(y_data))
    params, covariance = curve_fit(sine_wave, x_data,
                                   y_data,
                                   p0=initial_guess)

    A_fit, f_fit, phi_fit, C_fit = params

    # Generate fitted curve
    x_fit = np.linspace(0, len(x_data), 1000)
    y_fit = sine_wave(x_fit, A_fit, f_fit, phi_fit, C_fit)

    return x_fit, y_fit, A_fit


def sine_wave(x, A, f, phi, C):
    return A * np.sin(2 * np.pi * f * x + phi) + C


def plot_raw_bufs_df(raw_wfms_df):
    fig, axes = plt.subplots(2, 4, sharex=True, sharey=True)
    fig.set_size_inches(25, 7)
    raw_wfms_df['adc0'].plot(ax=axes[0][0], label='SLED FWD', legend=True)
    raw_wfms_df['adc1'].plot(ax=axes[0][1], label='KLY FWD', legend=True)
    raw_wfms_df['adc2'].plot(ax=axes[0][2], label='KLY REV', legend=True)
    raw_wfms_df['adc3'].plot(ax=axes[0][3], label='PRL', legend=True)
    raw_wfms_df['adc4'].plot(ax=axes[1][0], label='SSSB', legend=True)
    raw_wfms_df['adc5'].plot(ax=axes[1][1], label='Spare', legend=True)
    raw_wfms_df['adc6'].plot(ax=axes[1][2], label='Beam Voltage', legend=True)
    raw_wfms_df['adc7'].plot(ax=axes[1][3], label='Beam Current', legend=True)
    axes[0][0].set_ylabel("Amplitude [Counts]")
    axes[1][0].set_ylabel("Amplitude [Counts]")
    for row in axes:
        for ax in row:
            ax.legend(loc="upper right")


def plot_iq_wfms_df(df_iq, ylim_amp=(-100, 40000), len_ns=9000):
    ylim_phs = (-200, 200)
    fig, axes = plt.subplots(2, 3, sharex=True)
    fig.set_size_inches(20, 10)
    for i in range(10):
        if i > 7:
            ch = 'drv' + str(i - 8)
            df_iq[[ch + '_amp']].loc[:len_ns].plot(ax=axes[0][2],
                                                   ylim=ylim_amp)
            df_iq[[ch + '_phs']].loc[:len_ns].plot(ax=axes[1][2],
                                                   ylim=ylim_phs)
        else:
            c = i // 4
            ch = 'adc' + str(i)
            df_iq[[ch + '_amp']].loc[:len_ns].plot(ax=axes[0][c],
                                                   ylim=ylim_amp)
            df_iq[[ch + '_phs']].loc[:len_ns].plot(ax=axes[1][c],
                                                   ylim=ylim_phs)
    ax_list = axes.flatten()
    for ax in ax_list:
        ax.legend(loc='upper right')
