from leep.raw import LEEPDevice
from llrf_app.bsp import MarbleDevInfo
import numpy as np
import json
import time
import logging
logger = logging.getLogger(__name__)


class LLRFApp(LEEPDevice):
    def __init__(self, addr='192.168.19.42:803', conf='LEMP',
                 settings_fname='../llrf_dsp/settings.json',
                 chan_keep=0x3ff, wfm_len=4096,
                 timeout=0.1, **kwargs):
        self.init_rom_addr = 0x04000
        super(LLRFApp, self).__init__(addr, timeout, **kwargs)

        with open(settings_fname) as f:
            configs = json.load(f)
        for k, v in configs[conf].items():
            setattr(self, k.lower(), v)
        self.wave_samp_per = 1
        self.wfm_len = wfm_len
        assert self.wfm_len <= 2**15  # cbuf size / 2
        self.ts = self.dsp_clk_cycle * self.cic_base_period
        self.ts *= self.wave_samp_per
        self.chan_keep = chan_keep & 0x03ff  # 2 dacs, 8 adcs
        self.n_chan = bin(self.chan_keep).count('1')
        self.adc_names = [f'ADC {i}' for i in range(8)]
        self.dac_names = ['DAC 0', 'DAC 1']
        self.chan_names = self.adc_names + self.dac_names
        self.marble_info = MarbleDevInfo()
        self.init_demo()

    def init_demo(self):
        self.reg_write([
            ('amp_setpoint', 30000),
            ('dac_permit', 1),
            ('wave_samp_per', self.wave_samp_per),
            ('chan_keep', self.chan_keep)
        ])
        logger.debug(f'chan_keep: {self.chan_keep:#018b}')
        self.chans = np.where(
            np.array([int(x) for x in f'{self.chan_keep:b}'[::-1]]) == 1)[0]
        logger.debug(f'chans selected: {self.chans}')

    def read_reg(self, name):
        ''' read single register by given name '''
        return self.reg_read([name])[0]

    def write_reg(self, name, val):
        ''' read single register by given name '''
        return self.reg_write([(name, val)])

    def get_bsp_info(self):
        self.marble_info.decode_data(self.read_reg('bsp_info_buf'))
        return self.marble_info

    def read_adc_bufs(self):
        return np.array(self.reg_read([
            'adc' + str(chan) + '_buf' for chan in range(8)
            ]), dtype=np.int16)

    def read_dac_bufs(self):
        return np.array(self.reg_read([
            'dac' + str(chan) + '_buf' for chan in range(2)
            ]), dtype=np.int16)

    def read_cbuf_data(self):
        self.write_reg('circle_buf_flip', 1)
        while (self.read_reg('llrf_circle_ready') != 3):
            time.sleep(0.01)
        d = np.array(self.read_reg('circle_data'))
        return d[:self.wfm_len * 2 * self.n_chan]

    def get_mp_wfm(self):
        darray = self.read_cbuf_data()
        iq_traces = self.calc_iq_arrays(darray)
        return self.calc_mp_traces(iq_traces)

    def calc_iq_arrays(self, varray):
        darray = varray.reshape(-1, 2*self.n_chan).T
        iq_arrays = np.array([
            (darray[ix*2] + 1j * darray[ix*2+1])
            for ix in range(self.n_chan)]) / self.amp_rx_gain
        return iq_arrays

    def calc_mp_traces(self, iq_arrays):
        mag_trace = np.abs(iq_arrays)
        phs_trace = np.angle(iq_arrays, deg=True)
        return np.vstack((mag_trace, phs_trace))
