from leep.raw import LEEPDevice
from uspas_llrf import dsp_config, LLRFShell, DacDriveSel
from uspas_llrf.app.bsp import MarbleDevInfo
from uspas_llrf.model.slow_bridge import decode_slow_data, SlowData
import numpy as np
from scipy import signal
import pandas as pd
import time
import logging
logger = logging.getLogger(__name__)


class LLRFApp(LEEPDevice):
    def __init__(self, addr='192.168.19.42:803', conf='LEMP',
                 chan_keep=0x3ff,
                 wave_samp_per=1,
                 loopback_test=False,
                 assert_system_bist=True,
                 timeout=0.1, **kwargs):
        self.init_rom_addr = 0x04000
        super().__init__(addr, timeout, **kwargs)

        config = dsp_config[conf]
        self.loopback_test = loopback_test
        if loopback_test:
            # set tx dds for dac_if to match adc_if for loopback test
            config['TX_NUM_DDS'] = config['NUM_DDS']
            config['TX_DEN_DDS'] = config['DEN_DDS'] * 2
        self.config = config
        self.app_name = f'{conf}_LLRF'
        self.n_dac, self.n_adc = 2, 8

        self.wave_samp_per = wave_samp_per
        self.chan_keep = chan_keep

        self.model = LLRFShell(self.config, wave_samp_per=wave_samp_per)
        self.cic_base_period = self.config['CIC_BASE_PERIOD']
        self.dsp_clk_ns = self.config['DSP_CLK_CYCLE']
        self.fs = 1e9 / self.dsp_clk_ns
        self.signals = [f'adc{n}' for n in range(self.n_adc)] + \
            [f'drv{n}' for n in range(self.n_dac)]

        self.marble_info = MarbleDevInfo()
        if assert_system_bist:
            assert self.read_reg('system_bist_pass'), \
                "System Boot Self-Test Failed!"
        if loopback_test:
            init_regs = self.model.init_regs
            self.reg_write([
                ('tx_dds_phase_step', init_regs.tx_dds_phase_step),
                ('tx_dds_phase_shift', init_regs.tx_dds_phase_shift),
                ('tx_dds_modulo', init_regs.tx_dds_modulo),
                ('tx_phase_offset', init_regs.tx_phase_offset)
            ])
            logger.warning('IF loop back testing: IF_dac equals IF_adc.')

    @property
    def wave_samp_per(self):
        self._wave_samp_per = self.read_reg('wave_samp_per')
        return self._wave_samp_per

    @wave_samp_per.setter
    def wave_samp_per(self, value):
        assert value <= 127, "Max wave_samp_per is 127"
        self.model = LLRFShell(self.config, wave_samp_per=value)
        self.reg_write([
            ('wave_samp_per', self.model.cic_mon.wave_samp_per),
            ('cic_wave_shift', self.model.cic_mon.wave_shift)
        ])

    @property
    def chan_keep(self):
        self._chan_keep = self.read_reg('chan_keep')
        return self._chan_keep

    @chan_keep.setter
    def chan_keep(self, value):
        self.write_reg('chan_keep', value)
        self._chan_keep = value

    @property
    def cic_n_chan(self):
        return bin(self.chan_keep).count('1')

    @property
    def cic_ts_ns(self):
        """CIC waveform time period in ns"""
        return self.dsp_clk_ns * self.cic_base_period * self.wave_samp_per

    @property
    def cic_names(self):
        cic_chans = [int(b) for b in f'{self.chan_keep:010b}'][::-1]
        return [self.signals[i] for i, en in enumerate(cic_chans) if en]

    @property
    def dac_drive_sel(self):
        self._dac_drive_sel = self.read_reg('dac_drive_sel')
        return DacDriveSel(self._dac_drive_sel).name

    @dac_drive_sel.setter
    def dac_drive_sel(self, value):
        assert value in [0, 1, 2, 3], f"Invalid value: {value}"
        self.write_reg('dac_drive_sel', value)
        self._dac_drive_sel = value

    def __repr__(self):
        str = (f"< {self.__class__.__name__:8s}:   {self.app_name} >\n"
               f"dsp_clk:       {self.fs / 1e6:8.3f} MHz, \n"
               f"dac_clk:       {2 * self.fs / 1e6:8.3f} MHz, \n"
               f"wave_samp_per: {self.wave_samp_per}, \n"
               f"cic_sigs:      {self.cic_names}, \n"
               f"dac_drive_sel: {self.dac_drive_sel}\n")
        if self.loopback_test:
            str += "--== IF LOOP BACK TESTING MODE! ==--\n"
        return str

    def init_cw_demo(self):
        """ Setup demo in CW mode, bypass interlocks"""
        self.reg_write([
            ('inlk_permit_mask', 0),  # bypass interlocks
            ('arc_permit_mask', 0),  # bypass interlocks
            ('ext_permit_bypass', 1),  # bypass external permits
            ('pulse_modes', 0),
            ('soft_drive_enable', 3),
            ('wave_samp_per', self.wave_samp_per),
            ('chan_keep', self.chan_keep)
        ])
        logger.debug(f'chan_keep: {self.chan_keep:#018b}')

    def init_loop(self, loop='loop0', close_loop=False,
                  amp_setp_adc=2e4, phs_setp_deg=0,
                  kp_amp=1000, ki_amp=100,
                  kp_phs=1000, ki_phs=100):
        if close_loop:
            amp_setp, phs_setp = self.model.calc_close_loop_setp(
                amp_setp_adc, phs_setp_deg)
        else:
            amp_setp, phs_setp = self.model.calc_open_loop_setp(
                amp_setp_adc, phs_setp_deg)
        self.reg_write([
            (f'{loop}_amp_setpoint', amp_setp),
            (f'{loop}_phs_setpoint', phs_setp),
            (f'{loop}_Kp_amp', kp_amp),
            (f'{loop}_Ki_amp', ki_amp),
            (f'{loop}_Kp_phs', kp_phs),
            (f'{loop}_Ki_phs', ki_phs),
        ])

    def close_loop(self, loop='loop0'):
        self.reg_write([
            (f'{loop}_amp_reset', True),
            (f'{loop}_phs_reset', True),
            (f'{loop}_amp_enable', True),
            (f'{loop}_phs_enable', True),
            (f'{loop}_amp_reset', False),
            (f'{loop}_phs_reset', False),
        ])

    def open_loop(self, loop='loop0'):
        self.reg_write([
            (f'{loop}_amp_enable', False),
            (f'{loop}_phs_enable', False),
        ])

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
        phs = self.model.decode_phase(df['mon_phs'].to_numpy(), width=17, deg=False)
        rfmon = df['mon_amp'] * np.exp(1j * phs) / inlk_gains
        df['Amp [cnt]'] = np.abs(rfmon)
        df['Phs [deg]'] = np.angle(rfmon, deg=True)
        return df

    def get_inlk_status(self):
        """ Read rf_pwr interlock status bits, amplitude thresholds and the
        fault record amplitude

        Thresholds and fault_amp are also given in ADC counts, divided by
        the interlock path gain.

        Bit n of each rf_pwr mask belongs to channel n of self.signals;
        1 is OK, 0 is tripped (see monitor_inlk.v).

        Returns:
            (DataFrame indexed by channel, rf_pwr_permit_sum bit)
        """
        masks = ['rf_pwr_status', 'rf_pwr_first_fault_status',
                 'rf_pwr_latch', 'inlk_permit_mask']
        amps = ['fault_amp', 'inlk_amp_lo', 'inlk_amp_hi']
        vals = self.reg_read(amps + masks + ['rf_pwr_permit_sum'])
        n_ch = len(self.signals)
        df = pd.DataFrame(index=self.signals)
        inlk_gains = [abs(self.model.inlk_gain)] * self.n_adc
        inlk_gains += [abs(self.model.inlk_tx_gain)] * self.n_dac
        for name, val in zip(amps, vals):
            df[name] = np.array(val)[:n_ch]
        df['Fault Amp [cnt]'] = df['fault_amp'] / inlk_gains
        df['Amp Lo [cnt]'] = df['inlk_amp_lo'] / inlk_gains
        df['Amp Hi [cnt]'] = df['inlk_amp_hi'] / inlk_gains
        for name, val in zip(masks, vals[len(amps):]):
            df[name] = [(int(val) >> ch) & 1 for ch in range(n_ch)]
        return df, int(vals[-1]) & 1

    def get_arc_status(self):
        """ Read arc detector interlock bits of the 3 arc channels

        1 is OK, 0 is tripped (see arc_inlk.v).

        Returns:
            (DataFrame indexed by arc channel, arc_permit_sum bit)
        """
        masks = ['arc_permit_raw', 'arc_permit_latch', 'arc_permit_mask']
        vals = self.reg_read(masks + ['arc_permit_sum'])
        n_arc = 3
        df = pd.DataFrame(index=[f'arc{n}' for n in range(n_arc)])
        for name, val in zip(masks, vals):
            df[name] = [(int(val) >> ch) & 1 for ch in range(n_arc)]
        return df, int(vals[-1]) & 1

    def get_permit_status(self):
        """ Read the RF permit chain bits (1 = permit, 0 = trip)

        drive_permit_out = (ext_permit_bypass | drive_permit_in &
        slow_permit_in) & rf_pwr_permit_sum & arc_permit_sum &
        hpa_permit_out; drive n is on with soft_drive_enable[n] &
        drive_permit_out (see llrf_shell.v).

        Returns:
            dict of register name to int
        """
        names = ['drive_permit_in', 'slow_permit_in', 'ext_permit_bypass',
                 'rf_pwr_permit_sum', 'arc_permit_sum', 'hpa_permit_out',
                 'drive_permit_out', 'soft_drive_enable']
        return {n: int(v) for n, v in zip(names, self.reg_read(names))}

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
        df['Time [ns]'] = np.arange(sig_wfms.shape[-1]) * self.dsp_clk_ns
        df.set_index('Time [ns]', inplace=True)
        return df

    def read_iq_wfms(self):
        """ Read I, Q waveforms of all waveforms in ADC count unit.
            Returns a 2D array of shape (n_chan, 4096)
        """
        self.write_reg('sig_buf_flip', 1)
        while (self.read_reg('sig_iq_buf_ready') != 0xfffff):
            time.sleep(0.001)
        iq_wfms = np.array(self.reg_read(
            [f'{ch}_i_buf' for ch in self.signals]
            + [f'{ch}_q_buf' for ch in self.signals]))
        wfms = iq_wfms[:len(self.signals)] + 1j * iq_wfms[len(self.signals):]
        wfms[:self.n_adc] /= self.model.rx_iq_gain
        wfms[-self.n_dac:] *= self.model.tx_iq_gain
        logger.debug(f"Read {wfms.shape[0]} IQ waveforms, length {wfms.shape[1]}")
        return wfms

    def get_iq_wfms_df(self):
        """returns a DataFrame of all IQ waveforms, in ADC count unit"""
        iq_wfms = self.read_iq_wfms()
        df = pd.DataFrame(iq_wfms.T, columns=self.signals)
        df['Time [ns]'] = np.arange(iq_wfms.shape[-1]) * self.dsp_clk_ns
        df.set_index('Time [ns]', inplace=True)
        for ch in self.signals:
            df[f'{ch}_amp'] = np.abs(df[ch])
            df[f'{ch}_phs'] = np.angle(df[ch], deg=True)
        return df

    def wait_circle_ready(self, mask=0b11, timeout=1.0):
        """Wait for llrf_circle_ready bits {slow_ready, cbuf_ready}."""
        t0 = time.monotonic()
        while (self.read_reg('llrf_circle_ready') & mask) != mask:
            if time.monotonic() - t0 > timeout:
                raise TimeoutError(
                    f'llrf_circle_ready mask {mask:#04b} not set in {timeout} s')
            time.sleep(0.01)

    def read_slow_data(self, flip=False):
        """Read and decode the slow_bridge diagnostics block.

        The block is snapshot on the buffer transfer selected by
        slow_snap_cic: cic_waves (CW LLRF) or IQ waveforms (pulsed LLRF).
        With flip=False it returns the data of the last transferred buffer,
        so call it right after read_cbuf_data() / read_iq_wfms() to get the
        status belonging to that waveform. With flip=True a circle buffer
        flip is issued first (only meaningful when slow_snap_cic=1).

        Returns:
            SlowData with cbuf status, tags, adc min/max, EVR timestamp,
            cycle counter and a `fault` flag (record stopped by record_en).
        """
        if flip:
            self.write_reg('circle_buf_flip', 1)
        self.wait_circle_ready(mask=0b10)
        words = np.asarray(self.read_reg('dsp_slow_data'))
        slow = decode_slow_data(words, n_adc=self.n_adc)
        logger.debug(f'slow data: {slow}')
        return slow

    def get_slow_data(self, flip=False) -> SlowData:
        return self.read_slow_data(flip=flip)

    def get_slow_df(self, flip=False):
        """Returns a DataFrame of ADC min/max from the slow block, with the
        decoded status words attached in df.attrs['slow']."""
        slow = self.read_slow_data(flip=flip)
        df = pd.DataFrame(
            {'adc_min': slow.adc_min, 'adc_max': slow.adc_max},
            index=self.signals[:self.n_adc])
        df['adc_pp'] = df['adc_max'] - df['adc_min']
        df.attrs['slow'] = {
            'fault': slow.fault, 'buf_wrap': slow.buf_wrap,
            'last_addr': slow.last_addr, 'cbuf_count': slow.cbuf_count,
            'tag': slow.tag, 'tag_old': slow.tag_old,
            'tag_changed': slow.tag_changed,
            'evr_seconds': slow.evr_seconds, 'evr_ticks': slow.evr_ticks,
            'cycles': slow.cycles}
        return df

    def read_cbuf_data(self, timeout=1.0):
        """Read the circle buffer, flipping first to request a new one.

        A flip returns the bank read last and arms the hand-over of the
        next completed buffer. In triggered modes (wave_trig_sel other than
        Always) a buffer only completes after a trigger, so the wait can
        time out. The request then stays armed and the next call waits
        without flipping again, since a second flip would discard a buffer
        that arrived in between.
        Raises TimeoutError if no buffer is handed over within timeout.
        """
        if not getattr(self, '_cbuf_armed', False):
            self.write_reg('circle_buf_flip', 1)
            self._cbuf_armed = True
        self.wait_circle_ready(mask=0b11, timeout=timeout)
        self._cbuf_armed = False
        d = np.array(self.read_reg('circle_data'))
        # total 2**16 samples, needs to truncate and reshape to (n_chan, 2**16/n_chan) for decoding
        max_samples = 2**16 // self.cic_n_chan // 2
        logger.debug(f"Truncating circle buffer data to {max_samples} samples per channel")
        return d[:max_samples * 2 * self.cic_n_chan]

    def get_cic_iq_wfms(self, timeout=1.0):
        darray = self.read_cbuf_data(timeout=timeout)
        return self.decode_interleaved_iq_wfm(darray)

    def decode_interleaved_iq_wfm(self, varray):
        darray = varray.reshape(-1, 2 * self.cic_n_chan).T
        iq_arrays = np.array([
            (darray[ix * 2] + 1j * darray[ix * 2 + 1])
            for ix in range(self.cic_n_chan)]) / self.model.cic_wfm_gain
        return iq_arrays

    def calc_mp_traces(self, iq_arrays):
        mag_trace = np.abs(iq_arrays)
        phs_trace = np.angle(iq_arrays, deg=True)
        return np.vstack((mag_trace, phs_trace))

    def get_cic_wfm_df(self, timeout=1.0):
        """Returns a DataFrame of circle buffer data"""
        cic_iq_wfms = self.get_cic_iq_wfms(timeout=timeout)
        df = pd.DataFrame(cic_iq_wfms.T, columns=self.cic_names)
        df['Time [ns]'] = np.arange(cic_iq_wfms.shape[-1]) * self.cic_ts_ns
        df.set_index('Time [ns]', inplace=True)
        for ch in self.cic_names:
            df[f'{ch}_amp'] = np.abs(df[ch])
            df[f'{ch}_phs'] = np.angle(df[ch], deg=True)
        return df

    def calc_psd_df(self, df_sig, fullscale=32767):
        fs = 1e9 / df_sig.index.diff()[1]
        fsdb = 20 * np.log10(fullscale / np.sqrt(2))
        f, pxx = signal.periodogram(
            df_sig.T, fs, 'flattop',
            scaling='spectrum', nfft=8192)
        psd_dbfs = 10 * np.log10(pxx) - fsdb
        df_psd = pd.DataFrame(psd_dbfs.T, columns=df_sig.columns)
        df_psd['Freq [Hz]'] = f
        df_psd.set_index('Freq [Hz]', inplace=True)
        return df_psd
