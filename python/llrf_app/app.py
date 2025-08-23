from leep.raw import LEEPDevice
from llrf_model.llrf_dsp import LLRFShell, wrap_phase
from llrf_app.bsp import MarbleDevInfo
import numpy as np
import pandas as pd
import json
import time
import logging
logger = logging.getLogger(__name__)


class LLRFApp(LEEPDevice):
    def __init__(self, addr='192.168.19.42:803', conf='LEMP',
                 settings_fname='../llrf_dsp/settings.json',
                 chan_keep=0x3ff, wfm_len=4096,
                 wave_samp_per=1,
                 timeout=0.1, **kwargs):
        self.init_rom_addr = 0x04000
        super().__init__(addr, timeout, **kwargs)

        with open(settings_fname) as f:
            configs = json.load(f)
        dsp_config = configs[conf]
        self.model = model = LLRFShell(dsp_config, wave_samp_per=wave_samp_per)
        self.wfm_len = wfm_len
        assert self.wfm_len <= 2**15  # cbuf size / 2
        self.cic_ts = model.DSP_CLK_CYCLE * model.CIC_BASE_PERIOD \
            * wave_samp_per
        self.n_dac, self.n_adc = 2, 8
        self.chan_keep = chan_keep
        self.cic_n_chan = bin(self.chan_keep).count('1')
        self.signals = [f'adc{n}' for n in range(self.n_adc)] + \
            [f'dac{n}' for n in range(self.n_dac)]
        self.cic_chans = [int(b) for b in f'{chan_keep:010b}'][::-1]
        self.cic_names = [self.signals[i] for i, en in
                          enumerate(self.cic_chans) if en]
        self.marble_info = MarbleDevInfo()
        self.init_demo()

    def init_demo(self):
        self.system_bist_pass = self.read_reg('system_bist_pass')
        assert self.system_bist_pass, "System Boot Self-Test Failed!"
        self.reg_write([
            ('amp_setpoint', 30000),
            ('dac_permit', 1),
            ('wave_samp_per', self.model.wave_samp_per),
            ('chan_keep', self.chan_keep)
        ])
        logger.debug(f'chan_keep: {self.chan_keep:#018b}')

    def read_reg(self, name):
        """ read a single register by given name """
        return self.reg_read([name])[0]

    def write_reg(self, name, val):
        """ write a single register by given name """
        return self.reg_write([(name, val)])

    def get_bsp_info(self):
        self.marble_info.decode_data(self.read_reg('bsp_info_buf'))
        return self.marble_info

    def get_rfmon(self):
        """ Read a snapshot of RF amp/phs measurements """
        cols = ['mon_amp', 'mon_phs']
        df = pd.DataFrame(
            data=np.array(self.reg_read(cols)).T[:len(self.signals)],
            index=self.signals, columns=cols)
        inlk_gains = [self.model.inlk_gain] * self.n_adc
        inlk_gains += [self.model.inlk_tx_gain] * self.n_dac
        phs = self.model.decode_phase(df['mon_phs'], width=17, deg=False)
        rfmon = df['mon_amp'] * np.exp(1j * phs) / inlk_gains
        df['Amp [cnt]'] = np.abs(rfmon)
        df['Phs [deg]'] = np.angle(rfmon, deg=True)
        return df

    def read_raw_bufs(self):
        self.write_reg('sig_buf_flip', 1)
        while (self.read_reg('sig_buf_ready') != 0xff):
            time.sleep(0.001)
        return np.array(self.reg_read(
            [f'{ch}_buf' for ch in self.signals[:self.n_adc]]), dtype=np.int16)

    def get_raw_bufs_df(self):
        """Returns a DataFrame of raw waveforms for 8 adc channels"""
        sig_wfms = self.read_raw_bufs()
        df = pd.DataFrame(sig_wfms.T, columns=self.signals[:self.n_adc])
        df['Time [ns]'] = np.arange(sig_wfms.shape[-1]) * \
            self.model.DSP_CLK_CYCLE
        df.set_index('Time [ns]', inplace=True)
        return df

    def read_iq_wfms(self):
        """ Read I, Q waveforms of all waveforms in ADC count unit.
            Returns a 2D array of shape (n_chan, wfm_len)
        """
        self.write_reg('sig_buf_flip', 1)
        while (self.read_reg('sig_iq_buf_ready') != 0xfffff):
            time.sleep(0.001)
        iq_wfms = np.array(self.reg_read(
            [f'{ch}_i_buf' for ch in self.signals] +
            [f'{ch}_q_buf' for ch in self.signals]))
        wfms = iq_wfms[:len(self.signals)] + 1j * iq_wfms[len(self.signals):]
        wfms[:self.n_adc] /= self.model.rx_iq_gain
        wfms[-self.n_dac:] *= self.model.tx_iq_gain
        return wfms

    def get_iq_wfms_df(self):
        """returns a DataFrame of all IQ waveforms, in ADC count unit"""
        iq_wfms = self.read_iq_wfms()
        df = pd.DataFrame(iq_wfms.T, columns=self.signals)
        df['Time [ns]'] = np.arange(iq_wfms.shape[-1]) * \
            self.model.DSP_CLK_CYCLE
        df.set_index('Time [ns]', inplace=True)
        for ch in self.signals:
            df[f'{ch}_amp'] = np.abs(df[ch])
            df[f'{ch}_phs'] = np.angle(df[ch], deg=True)
        return df

    def read_cbuf_data(self):
        self.write_reg('circle_buf_flip', 1)
        while (self.read_reg('llrf_circle_ready') != 3):
            time.sleep(0.01)
        d = np.array(self.read_reg('circle_data'))
        return d[:self.wfm_len * 2 * self.cic_n_chan]

    def get_cic_iq_wfms(self):
        darray = self.read_cbuf_data()
        return self.decode_interleaved_iq_wfm(darray)
        # return self.calc_mp_traces(iq_traces)

    def decode_interleaved_iq_wfm(self, varray):
        darray = varray.reshape(-1, 2*self.cic_n_chan).T
        iq_arrays = np.array([
            (darray[ix*2] + 1j * darray[ix*2+1])
            for ix in range(self.cic_n_chan)]) / self.model.cic_wfm_gain
        return iq_arrays

    def calc_mp_traces(self, iq_arrays):
        mag_trace = np.abs(iq_arrays)
        phs_trace = np.angle(iq_arrays, deg=True)
        return np.vstack((mag_trace, phs_trace))

    def get_cic_wfm_df(self):
        """Returns a DataFrame of circle buffer data"""
        cic_iq_wfms = self.get_cic_iq_wfms()
        df = pd.DataFrame(cic_iq_wfms.T, columns=self.cic_names)
        df['Time [ns]'] = np.arange(cic_iq_wfms.shape[-1]) * self.cic_ts
        df.set_index('Time [ns]', inplace=True)
        for ch in self.cic_names:
            df[f'{ch}_amp'] = np.abs(df[ch])
            df[f'{ch}_phs'] = np.angle(df[ch], deg=True)
        return df
