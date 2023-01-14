from leep.raw import LEEPDevice
import numpy as np
from matplotlib import pyplot as plt
import time
import matplotlib.animation as animation
import logging
np.set_printoptions(precision=0, suppress=True, edgeitems=4, linewidth=120)
logger = logging.getLogger(__name__)


class LLRFApp(LEEPDevice):
    def __init__(self, addr, timeout=0.1, **kwargs):
        self.init_rom_addr = 0x08000
        super(LLRFApp, self).__init__(addr, timeout, **kwargs)
        self.chan_keep = 0x03ff  # 2 dacs, 8 adcs
        self.adc_len = 4096
        self.n_chan = bin(self.chan_keep).count('1')
        self.wfm_len = 4096
        self.chan_names = [f'ADC {i}' for i in range(8)]
        self.chan_names += ['DAC 0', 'DAC 1']
        self.init_demo()

    def init_demo(self):
        self.reg_write([
            ('amp_setpoint', 30000),
            ('dac_permit', 1),
            ('wave_samp_per', 1),
            ('chan_keep', self.chan_keep)
        ])
        print(f'chan_keep: {self.chan_keep:#018b}')
        self.chans = np.where(
            np.array([int(x) for x in f'{self.chan_keep:b}'[::-1]]) == 1)[0]
        print(f'chans selected: {self.chans}')

    def read_reg(self, name):
        ''' read single register by given name '''
        return self.reg_read([name])[0]

    def write_reg(self, name, val):
        ''' read single register by given name '''
        return self.reg_write([(name, val)])

    def decode_twos_comp(self, darray, bits=16):
        mask = 2**(bits - 1)
        return -np.bitwise_and(darray, mask) + np.bitwise_and(darray, ~mask)

    def get_adc_wfm(self):
        yield self.read_adc_bufs()[:, :self.adc_len]

    def update_plot(self, darray):
        for line, ydata in zip(self.lines, darray):
            line.set_ydata(ydata)
        return self.lines

    def read_cbuf_data(self):
        self.write_reg('circle_buf_flip', 1)
        while (self.read_reg('llrf_circle_ready') & 1 != 1):
            time.sleep(0.01)
        d = np.array(self.read_reg('circle_data'))
        return d[:self.wfm_len * self.n_chan]

    def get_cbuf_wfm(self):
        yield self.read_cbuf_data()

    def update_cbuf_wfm(self, varray):
        darray = varray.reshape(-1, self.n_chan).T
        for line, ydata in zip(self.lines, darray):
            line.set_ydata(ydata)
        return self.lines

    def plot_cbuf_wfm(self):
        self.fig, self.axes = plt.subplots(
            nrows=self.n_chan, figsize=(10, 10), sharex=True, squeeze=True)
        self.fig.suptitle('adc chan: {}'.format(self.chans))

        self.lines = [ax.plot(
            np.arange(self.adc_len),
            np.zeros(self.adc_len), animated=True)[0] for ax in self.axes]

        for ix, ax in enumerate(self.axes):
            ax.set_ylim(-1 << 15, 1 << 15)
            ax.set_ylabel(self.chan_names[self.chans[ix]])
            ax.grid(color='grey', alpha=.5, linestyle='--')
        self.axes[-1].set_xlabel('#Trigger')
        # self.axes[0].autoscale(axis='y')

        self.anim = animation.FuncAnimation(
            self.fig, self.update_cbuf_wfm, self.get_cbuf_wfm,
            interval=5, blit=True, save_count=50)
