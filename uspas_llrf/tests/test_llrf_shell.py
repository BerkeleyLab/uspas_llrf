from uspas_llrf import (LLRFShell, DacDriveSel, LocalbusAppMaster,
                        InlkFaultMode, wrap_phase, clip_int, dsp_config)
import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from cocotb.handle import Immediate
import logging
import numpy as np
from dataclasses import asdict
from pprint import pformat
import itertools


class TB_llrf_shell:
    def __init__(self, dut, f_config='USPAS', wave_samp_per=1,
                 amp_exp=None, phs_exp=None,
                 regmap_json_path='llrf_shell.json'):
        dut._log.setLevel(logging.INFO)
        self.dut = dut
        self.cbuf_aw = dut.CBUF_AW.value.to_unsigned()
        self.sig_buf_aw = dut.SIG_BUF_AW.value.to_unsigned()
        self.f_config = f_config
        config = dsp_config[f_config]
        # Override tx dds setting for loopback test at IF_adc
        config['TX_NUM_DDS'] = config['NUM_DDS']
        config['TX_DEN_DDS'] = config['DEN_DDS'] * 2
        config['TX_SECOND_NYQUIST'] = False
        config['TX_AFE_SPECTRAL_FLIP'] = False
        # Force CW mode to allow loop tests
        config['PULSE_MODES'] = 0
        self.llrf = llrf = LLRFShell(config, wave_samp_per=wave_samp_per)
        self.lb = LocalbusAppMaster(
            dut, dut.lb_clk, regmap_json_path=regmap_json_path)
        self.log_banner(f'Simulating: {f_config}')
        cocotb.log.info(f'LLRF RX:\n{llrf.rx}')
        cocotb.log.info(f'LLRF TX:\n{llrf.tx}')
        cocotb.log.debug(f'Calibrations:\n{pformat(llrf.cal_factors)}')

        cocotb.start_soon(Clock(dut.lb_clk, 8, unit="ns").start())
        cocotb.start_soon(Clock(dut.gt_rxclk, 8, unit="ns").start())
        dsp_clk_period = round(llrf.config['DSP_CLK_CYCLE'], 1)
        cocotb.start_soon(
            Clock(dut.dsp_clk, dsp_clk_period, unit="ns").start())
        cocotb.start_soon(
            Clock(dut.dac_clk, dsp_clk_period / 2, unit="ns").start())

        # test bench setup
        self.loopback_dac, self.feedback_dac = 0, 1
        self.feedback_adc = self.llrf.feedback_adc
        self.phaseref_adc = self.llrf.phaseref_adc
        # pick a random available ADC channel for loopback test
        available_adcs = [
            ch for ch in range(8)
            if ch not in [self.phaseref_adc, self.feedback_adc]]
        self.loopback_adc = random.choice(available_adcs)
        cocotb.log.warning(
            f'phaseref_adc: {self.phaseref_adc}, '
            f'loopback_adc: {self.loopback_adc}')
        # flattened signal array of 2 DAC + 8 ADC
        self.sig_names = {
            8 + self.feedback_dac: 'feedback_dac',
            8 + self.loopback_dac: 'loopback_dac',
            self.loopback_adc: 'loopback_adc',
            self.feedback_adc: 'feedback_adc',
            self.phaseref_adc: 'phaseref_adc'}
        self.llrf.init_regs.chan_keep = \
            (1 << self.phaseref_adc | 1 << self.loopback_adc)
        self.cic_chans = [
            int(b) for b in f'{self.llrf.init_regs.chan_keep:010b}'][::-1]
        self.cic_n_chan = self.cic_chans.count(1)
        self.cic_names = [
            self.sig_names[idx] for idx, enabled in enumerate(self.cic_chans)
            if enabled]  # lsb_mask==1: first chan is LSB
        cocotb.log.warning(f'cic chans: {self.cic_chans}')
        cocotb.log.warning(f'cic names: {self.cic_names}')
        self.amp_exp, self.phs_exp = self.init_test(amp_exp, phs_exp)
        cocotb.start_soon(
            self.drive_phaseref_adc(
                self.phaseref_adc, self.amp_exp, self.phs_exp))
        cocotb.start_soon(
            self.loopback(self.loopback_dac, self.loopback_adc))
        cocotb.start_soon(
            self.loopback(self.feedback_dac, self.feedback_adc))

    def log_banner(self, str):
        cocotb.log.info('*' * 20 + f"{str:^20s}" + '*' * 20)

    def init_test(self, amp_exp=None, phs_exp=None):
        if amp_exp is None:
            amp_exp = self.llrf.cal_factors.max_adc_input
        else:
            assert amp_exp < self.llrf.cal_factors.max_adc_input, \
                f"amp_exp {amp_exp:.3f} too high. " \
                f"max value : {self.llrf.cal_factors.max_adc_input:.3f}"
        if phs_exp is None:
            phs_exp = random.randint(-180, 180)
        return amp_exp, phs_exp

    def check_sig(self, sig_meas, sig_name='signal'):
        """Check the measured signal against expected amplitude and phase."""
        amp_meas = np.abs(sig_meas)
        phs_meas = np.angle(sig_meas, deg=True)
        cocotb.log.warning(
            f"expected {sig_name:12s} mag: {self.amp_exp:8.2f} cnt,  "
            f"phs: {self.phs_exp:6.3f} deg")
        cocotb.log.warning(
            f"measured {sig_name:12s} mag: {amp_meas:8.2f} cnt,  "
            f"phs: {phs_meas:6.3f} deg")
        amp_err = abs(amp_meas - self.amp_exp) / self.amp_exp
        assert amp_err < 0.001, "amplitude out-of-bound of 0.1%"
        phs_err = abs(wrap_phase(phs_meas - self.phs_exp))
        assert phs_err < 0.1, "phase out-of-bound of 0.1 deg"

    async def drive_phaseref_adc(self, ch=0, amp=0.0, phs=0.0, noise_amp=3):
        # wait for dsp_reset
        dsp_reset = self.dut.llrf_shell.dsp_reset
        while True:
            await dsp_reset.value_change
            if dsp_reset.value == 0:  # falling edge
                break
        cocotb.log.warning("dsp_reset done. drive_phaseref_adc started.")
        # truly important but empirical to synchronize with DDS
        t_start = self.llrf.config['CIC_BASE_PERIOD'] % 22
        for t in itertools.count(t_start):
            await RisingEdge(self.dut.dsp_clk)
            sig = amp * np.exp(1j * (self.llrf.omega * t + np.deg2rad(phs)))
            noise = random.randint(-noise_amp, noise_amp)
            self.dut.adc_array_in[ch].value = clip_int(sig.real + noise)

    async def loopback(self, dac_chan=0, adc_chan=0):
        """ loopback dac_chan -> adc_chan with 0 cycle of latency """
        while True:
            await RisingEdge(self.dut.dsp_clk)
            self.dut.adc_array_in[adc_chan].set(Immediate(
                self.dut.dac_array_out[dac_chan].value.to_signed()))

    async def read_inlk_task(self, chan=0):
        """Read inlk amplitude and phase from the local bus. """
        amp = await self.lb.read_reg('mon_amp', chan)
        phs = await self.lb.read_reg('mon_phs', chan)
        phs = self.llrf.decode_phase(phs, width=17, deg=False)
        return amp * np.exp(1j * phs)

    async def read_cic_waveform(self, chan=0):
        """Read average of waveform data from the circle buffer. """
        await self.lb.write_reg('circle_buf_flip', 1)
        # wait for circle buffer ready, rely on timeout_time for exceptions
        await RisingEdge(self.dut.llrf_shell.cbuf_transferred)
        assert await self.lb.read_reg('llrf_circle_ready')
        wfm = []
        n_samples = (1 << self.cbuf_aw) // self.cic_n_chan // 2
        for idx in range(n_samples):
            offset = self.cic_n_chan * idx * 2  # 2 for I/Q
            i = await self.lb.read_reg('circle_data', offset + chan * 2)
            q = await self.lb.read_reg('circle_data', offset + chan * 2 + 1)
            wfm.append(i + 1j * q)
        return np.array(wfm, dtype=np.complex64)

    async def flip_sig_buf(self):
        """Flip the IQ waveform buffers and wait for the write side to hand
        over a new bank. Waits on sig_buf_iq_transferred[0] directly rather
        than slow_snap, which only follows it when slow_snap_cic=0.
        Rely on timeout_time for exceptions.
        """
        await self.lb.write_reg('sig_buf_flip', 1)
        transferred = self.dut.llrf_shell.sig_buf_iq_transferred
        while True:
            await transferred.value_change
            if transferred.value.to_unsigned() & 1:
                break
        assert await self.lb.read_reg('sig_buf_ready')

    async def snap_slow_data(self):
        """Flip the buffer the slow block is synchronized with, then wait
        for slow_ready. slow_snap_cic selects cbuf_transferred (CW LLRF
        using cic_waves) or sig_buf transfer (pulsed LLRF using IQ wfms).
        """
        if self.llrf.init_regs.slow_snap_cic:
            await self.read_cic_waveform()
        else:
            await self.flip_sig_buf()
        await self.wait_slow_ready()

    async def read_sig_buf(self, name='adc0_buf'):
        await self.flip_sig_buf()
        wfm = []
        for idx in range(1 << self.sig_buf_aw):
            s = await self.lb.read_reg(name, idx)
            wfm.append(s)
        return np.array(wfm)

    async def read_adc_min_max(self, chan=0):
        await self.snap_slow_data()
        min = await self.lb.read_reg('dsp_slow_adc_min', chan)
        max = await self.lb.read_reg('dsp_slow_adc_max', chan)
        return min, max

    async def write_init_regs(self):
        cocotb.log.debug(f'InitRegisters:\n{pformat(self.llrf.init_regs)}')
        for name, val in asdict(self.llrf.init_regs).items():
            await self.lb.write_reg(name, val)
        # single cycle, for resetting both up/down DDS
        await self.lb.write_reg('dsp_reset', 1)

    async def verify_init_regs(self):
        for name, val in asdict(self.llrf.init_regs).items():
            r = await self.lb.read_reg(name)
            assert r == val, f"Expected {name}:{val}, got {r}"

    def set_dac_drive_sel(self, loop='loop0'):
        """ drive loopback_dac and feedback_dac by the active loop """
        if loop == 'loop0':
            self.llrf.init_regs.dac_drive_sel = DacDriveSel.I0Q0
        elif loop == 'loop1':
            self.llrf.init_regs.dac_drive_sel = DacDriveSel.I1Q1

    async def test_open_loop(self, loop='loop0'):
        """
        Drive loopback_dac by 'loop' set points, check from loopback_adc
        """
        self.log_banner(f'Open Loop Test on {loop}')
        amp_setp, phs_setp = self.llrf.calc_open_loop_setp(
            self.amp_exp, self.phs_exp)
        setattr(self.llrf.init_regs, loop + '_amp_setpoint', amp_setp)
        setattr(self.llrf.init_regs, loop + '_phs_setpoint', phs_setp)
        self.set_dac_drive_sel(loop)
        await self.write_init_regs()
        await self.verify_init_regs()

        await self.read_cic_waveform()  # flush buffer recorded across reconfiguration
        self.log_banner('CIC Waveform')
        for i, name in enumerate(self.cic_names):
            cic_meas = await self.read_cic_waveform(i)
            self.check_sig(cic_meas.mean() / self.llrf.cic_wfm_gain, sig_name=name)

        self.log_banner('IQ Waveform')
        i_buf = await self.read_sig_buf(f'adc{self.phaseref_adc}_i_buf')
        q_buf = await self.read_sig_buf(f'adc{self.phaseref_adc}_q_buf')
        iq_avg = np.mean(i_buf + 1j * q_buf)
        gain = self.llrf.cal_factors.rx_gain / self.llrf.CORDIC_GAIN
        self.check_sig(iq_avg / gain, sig_name='phaseref_adc')

        self.log_banner('Min / Max')
        for chan in [self.phaseref_adc, self.loopback_adc]:
            min, max = await self.read_adc_min_max(chan)
            assert abs(-self.amp_exp - min) / self.amp_exp < 0.1, \
                "ADC min out of range"
            assert abs(self.amp_exp - max) / self.amp_exp < 0.1, \
                "ADC min out of range"
            cocotb.log.warning(
                f"measured {self.sig_names[chan]:12s} min: {min:8.2f} cnt,  "
                f"max: {max:6.2f} cnt")

        self.log_banner('RF Monitors for Interlock')
        for chan in [self.phaseref_adc, self.loopback_adc]:
            inlk_meas = await self.read_inlk_task(chan)
            self.check_sig(inlk_meas / self.llrf.inlk_gain,
                           sig_name=self.sig_names[chan])

        # check base band loop output, drive_i_out / drive_q_out
        # assign sig_i_data[N_ADC+ch] = drive_i_out[ch];
        # assign sig_q_data[N_ADC+ch] = drive_q_out[ch];
        if loop == 'loop0':
            chan = 8
        elif loop == 'loop1':
            chan = 9
        inlk_meas = await self.read_inlk_task(chan)
        self.check_sig(inlk_meas / self.llrf.inlk_tx_gain,
                       sig_name=self.sig_names[chan])

    async def test_close_loop(self, loop='loop0', wait=2000):
        """
        Drive feedback_dac by 'loop' set points, check from feedback_adc
        """
        self.log_banner(f'Close Loop Test on {loop}')
        amp_setp, phs_setp = self.llrf.calc_close_loop_setp(
            self.amp_exp, self.phs_exp)
        # Setup loop parameters
        regs = [
            (loop + '_amp_setpoint', amp_setp),
            (loop + '_phs_setpoint', phs_setp),
            (loop + '_Kp_amp', 2000),
            (loop + '_Kp_phs', 5000),
            (loop + '_Ki_amp', 100),
            (loop + '_Ki_phs', 500),
        ]
        for name, val in regs:
            setattr(self.llrf.init_regs, name, val)
        self.set_dac_drive_sel(loop)
        await self.write_init_regs()
        await self.verify_init_regs()
        # Close loop
        regs = [
            (loop + '_amp_reset', 1),
            (loop + '_phs_reset', 1),
            (loop + '_amp_enable', 1),
            (loop + '_phs_enable', 1),
            (loop + '_amp_reset', 0),
            (loop + '_phs_reset', 0),
        ]
        for name, val in regs:
            await self.lb.write_reg(name, val)
        await ClockCycles(self.dut.dsp_clk, wait)  # settling time of loops
        inlk_meas = await self.read_inlk_task(self.feedback_adc)
        self.check_sig(inlk_meas / self.llrf.inlk_gain,
                       sig_name='feedback_adc')

    async def trip_fast_interlock(self):
        """Arm a 99% to 101% window around the reference ADC amplitude
        with LoHi mode, so the fast interlock trips, inlk_permit_out drops
        and with it sum_drive_enable (record_en of cic_waves).
        """
        inlk_gain_abs = np.abs(self.llrf.inlk_gain)
        amp_lo = self.amp_exp * inlk_gain_abs * 0.99
        amp_hi = self.amp_exp * inlk_gain_abs * 1.01
        regs = [
            ('inlk_inlk_mode', self.phaseref_adc, InlkFaultMode.LoHi),
            ('inlk_amp_lo', self.phaseref_adc, amp_lo),
            ('inlk_amp_hi', self.phaseref_adc, amp_hi),
        ]
        for name, offset, val in regs:
            await self.lb.write_reg(name, val, offset)
        await self.lb.write_reg('inlk_permit_mask', 1 << self.phaseref_adc)
        await self.lb.write_reg('inlk_reset_inlk', 1)

    async def release_fast_interlock(self):
        """Restore inlk_permit_mask from init_regs and clear the latch."""
        await self.lb.write_reg(
            'inlk_permit_mask', self.llrf.init_regs.inlk_permit_mask)
        await self.lb.write_reg('inlk_reset_inlk', 1)

    async def wait_drive_permit(self, expected, max_reads=50):
        """Poll rf_pwr_permit_sum (inlk_permit_out) until it reads expected.

        drive_permit_out would be the direct readback of sum_drive_enable,
        but it sits behind jit_rad_gateway and needs lb_prefill, which the
        test wrapper ties low. test_llrf_shell.sv ties the external and
        arc permits high, so inlk_permit_out equals sum_drive_enable, the
        record_en of cic_waves; cross-check that on the internal wire.
        """
        for _ in range(max_reads):
            if await self.lb.read_reg('rf_pwr_permit_sum') == expected:
                break
        else:
            raise AssertionError(f'rf_pwr_permit_sum did not reach {expected}')
        await RisingEdge(self.dut.dsp_clk)
        record_en = int(self.dut.llrf_shell.sum_drive_enable.value)
        assert record_en == expected, \
            f'sum_drive_enable (record_en) is {record_en}, expected {expected}'

    async def wait_slow_ready(self, max_reads=50):
        """Poll llrf_circle_ready until slow_ready (bit 1) is set."""
        for _ in range(max_reads):
            if await self.lb.read_reg('llrf_circle_ready') & 0b10:
                return
        raise AssertionError('slow_ready never set')

    # dsp_slow_cbuf_stat1 = {record_type, buff_wrap, save_addr}, see circle_buf.v
    # record_type is the MSB of the 16-bit word (bit 16 counting from 1):
    # 1 = normal comfort display record, 0 = fault record (stopped by buf_stop)
    CBUF_STAT1_RECORD_TYPE = 1 << 15

    async def read_cbuf_stat1(self):
        """Flip the circle buffer, wait for the slow block and read stat1.

        Requires slow_snap_cic=1 so the slow block snapshots on
        cbuf_transferred and the status belongs to the waveform just read.
        """
        await self.snap_slow_data()
        stat1 = await self.lb.read_reg('dsp_slow_cbuf_stat1')
        stat2 = await self.lb.read_reg('dsp_slow_cbuf_stat2')
        count = await self.lb.read_reg('dsp_slow_cbuf_count')
        fault = not (stat1 & self.CBUF_STAT1_RECORD_TYPE)
        cocotb.log.warning(
            f'dsp_slow_cbuf_stat1: 0x{stat1:04x} stat2: 0x{stat2:04x} '
            f'count: {count} fault: {fault}')
        return stat1

    async def check_fault_amp(self):
        """Read the fault record amplitude latched by monitor_inlk at the
        drop of record_status_en and check it against the dsp_clk side
        latch and the LoHi window that tripped the reference ADC.
        """
        n_ch = len(self.dut.adc_array_in) + len(self.dut.dac_array_out)
        for ch in range(n_ch):
            amp = await self.lb.read_reg('fault_amp', ch)
            fault_amp_r = self.dut.llrf_shell.fault_amp_r.value
            expected = fault_amp_r[16 * ch + 15:16 * ch].to_signed()
            assert amp == expected, \
                f'fault_amp[{ch}] reads {amp}, latched {expected}'
        amp = await self.lb.read_reg('fault_amp', self.phaseref_adc)
        inlk_gain_abs = np.abs(self.llrf.inlk_gain)
        amp_lo = self.amp_exp * inlk_gain_abs * 0.99
        amp_hi = self.amp_exp * inlk_gain_abs * 1.01
        cocotb.log.warning(
            f'fault_amp[{self.phaseref_adc}]: {amp}, '
            f'window: {amp_lo:.0f} to {amp_hi:.0f}')
        assert amp_lo <= amp <= amp_hi, \
            f'fault_amp {amp} outside trip window {amp_lo:.0f} to {amp_hi:.0f}'

    async def test_record_stop(self, loop='loop0', post_delay=1):
        """Test waveform freeze on loss of drive permit.

        record_en of cic_waves is sum_drive_enable. Tripping the fast
        interlock drops it; after cbuf_post_delay buffer syncs the circle
        buffer stops writing and the record is flagged as a fault in
        dsp_slow_cbuf_stat1 (record_type bit cleared). Releasing the
        interlock and reading the buffer out resumes normal recording.
        """
        self.log_banner('Record Stop Test')
        self.set_dac_drive_sel(loop)
        assert self.llrf.init_regs.slow_snap_cic, \
            'test_record_stop needs SLOW_SNAP_CIC=1 (slow block on cbuf_transferred)'
        # post_delay=0 never generates buf_stop, see cic_waves.v
        await self.lb.write_reg('cbuf_post_delay', post_delay)
        # test_fast_interlock may have left the permit tripped
        await self.release_fast_interlock()
        await self.wait_drive_permit(1)
        await self.read_cbuf_stat1()  # discard, may be recorded while tripped
        stat1 = await self.read_cbuf_stat1()
        assert stat1 & self.CBUF_STAT1_RECORD_TYPE, \
            'buffer flagged as fault record while record_en is high'

        await self.trip_fast_interlock()
        await self.wait_drive_permit(0)  # record_en low
        cbuf_sync = self.dut.llrf_shell.cbuf_sync
        for _ in range(post_delay + 2):
            await RisingEdge(cbuf_sync)
        stat1 = await self.read_cbuf_stat1()
        assert not (stat1 & self.CBUF_STAT1_RECORD_TYPE), \
            'buffer not flagged as fault record after record_en dropped'

        await self.release_fast_interlock()
        await self.wait_drive_permit(1)
        await self.read_cbuf_stat1()  # discard, recording resumes on this flip
        stat1 = await self.read_cbuf_stat1()
        assert stat1 & self.CBUF_STAT1_RECORD_TYPE, \
            'buffer still flagged as fault record after record_en restored'

    async def test_fast_interlock(self, loop='loop0'):
        """Test monitor_inlk.v
        - Set threshold window to be between 99% and 101% around the expected
        reference ADC amplitude value.
        - Set inlk_mode to trip permit if lo < V < hi
        - Set inlk_permi_mask to only include reference ADC
        - Expect inlk_permit_out to be zero at the test condition

        Args:
            loop (str, optional): loop back drive source. Defaults to 'loop0'.
        """
        self.log_banner('Fast Interlock Test')
        self.set_dac_drive_sel(loop)
        inlk_gain_abs = np.abs(self.llrf.inlk_gain)
        await self.trip_fast_interlock()

        dut = self.dut.llrf_shell
        await RisingEdge(dut.inlk.wave_valid)
        cocotb.log.info("%8s " * 9 % (
            'chan', 'mon_amp', 'amp_lo', 'amp_hi', '>=lo', '>=hi',
            'permit', 'amp', 'phs'))
        for _ in range(20):
            await RisingEdge(self.dut.dsp_clk)
            mon_addr = dut.mon_addr_out.value.to_unsigned()
            mon_amp_out = dut.mon_amp_out.value.to_signed()
            mon_phs_cnt = dut.mon_phs_out.value.to_signed()
            mon_phs_out = self.llrf.decode_phase(mon_phs_cnt, width=17)
            amp_valid = dut.inlk.wave_cnt.value.to_unsigned() % 2 == 1
            if dut.inlk.wave_valid.value == 1 and amp_valid:
                cocotb.log.info(
                    f"{mon_addr:8d} "
                    f"{mon_amp_out:8d} "
                    f"{dut.inlk.amp_lo.value.to_unsigned():8d} "
                    f"{dut.inlk.amp_hi.value.to_unsigned():8d} "
                    f"{int(dut.inlk.cmpg_lo.value):8d} "
                    f"{int(dut.inlk.cmpg_hi.value):8d} "
                    f"{int(dut.inlk_permit_out.value):8d} "
                    f"{mon_amp_out / inlk_gain_abs:8.1f} "
                    f"{mon_phs_out:8.1f} ")
        assert dut.inlk_permit_out.value == 0, \
            "Unexpected inlk_permit_out."
        if hasattr(self.lb.reg_map, 'fault_amp'):
            await self.wait_drive_permit(0)  # record_status_en low
            await self.check_fault_amp()
