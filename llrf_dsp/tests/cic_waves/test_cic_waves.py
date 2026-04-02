import numpy as np
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from uspas_llrf import dsp_config, wrap_phase, CICWaveRecorder, LocalBusMaster


class TB:
    def __init__(self, dut, conf='USPAS', wave_samp_per=2, chan_keep=0b11):
        self.dut = dut
        self.config = dsp_config[conf]
        for k, v in self.config.items():
            setattr(self, k, v)
        self.wave_samp_per = wave_samp_per
        self.chan_keep = chan_keep

        self.cic_inlk = CICWaveRecorder(
            num=self.NUM_DDS, den=self.DEN_DDS,
            cic_base_period=self.CIC_BASE_PERIOD,
            shift_base=self.INLK_SHIFT_BASE)
        self.cic_mon = CICWaveRecorder(
            num=self.NUM_DDS, den=self.DEN_DDS,
            cic_base_period=self.CIC_BASE_PERIOD,
            shift_base=self.CIC_SHIFT_BASE,
            wave_samp_per=self.wave_samp_per)
        self.lb = LocalBusMaster(dut, dut.lb_clk)
        self.dsp_clk = dut.dsp_clk
        self.lb_clk = dut.lb_clk

        attrs = ['N_CH', 'N_ADC', 'CBUF_AW',
                 'P_ADDR_CBUF_DATA_BASE', 'P_ADDR_CBUF_READY', 'P_ADDR_CBUF_TRANSFERED',
                 'P_ADDR_CBUF_FLIP']
        for attr in attrs:
            setattr(self, attr, getattr(dut, attr).value.to_unsigned())

        cocotb.start_soon(Clock(self.dsp_clk, 8, unit='ns').start())
        cocotb.start_soon(Clock(self.lb_clk, 8, unit='ns').start())

    async def reset(self):
        dut = self.dut
        dut.dsp_reset.value = 1
        dut.iq_dval.value = 0
        dut.ext_trig.value = 0
        dut.inlk_permit_in.value = 1
        dut.cbuf_buf_flip.value = 0
        dut.lb_read.value = 0
        dut.lb_addr.value = 0

        await ClockCycles(self.dsp_clk, 10)
        dut.dsp_reset.value = 0
        await RisingEdge(self.dsp_clk)

    async def configure(self):
        dut = self.dut
        dut.cic_wave_samp_per.value = self.wave_samp_per
        dut.cic_base_period.value = self.CIC_BASE_PERIOD
        dut.cic_chan_keep.value = self.chan_keep
        dut.cic_wave_shift.value = self.cic_mon.wave_shift
        dut.inlk_wave_shift.value = self.cic_inlk.wave_shift
        dut.cbuf_post_delay.value = 0
        dut.dsp_tag.value = 0
        self.cic_chans = [
            int(b) for b in f'{self.chan_keep:010b}'][::-1]
        self.cic_n_chan = self.cic_chans.count(1)
        for ch in range(self.N_ADC):
            dut.slow_bridge_data_in[ch].value = 0

    async def pulse_ext_trig(self):
        dut = self.dut
        dut.ext_trig.value = 1
        await RisingEdge(self.dsp_clk)
        dut.ext_trig.value = 0

    async def set_wave_trig_sel(self, trig_sel='WAVE_TRIG_ALWAYS'):
        dut = self.dut
        v = getattr(dut, trig_sel).value.to_unsigned()
        dut.wave_trig_sel.value = v
        await RisingEdge(self.dsp_clk)

    async def stream_iq_data(self, sample_count=512, i=100, q=200):
        dut = self.dut

        dut.iq_dval.value = 1
        for sample in range(sample_count):
            for ch in range(self.N_CH):
                dut.iq_data[2 * ch].value = int(i)
                dut.iq_data[2 * ch + 1].value = int(q)
            for ch in range(self.N_ADC):
                dut.slow_bridge_data_in[ch].value = (sample + ch) & 0xFFFF
            await RisingEdge(self.dsp_clk)

    async def read_cic_waveform(self, chan=0):
        dut = self.dut

        await self.lb.write(self.P_ADDR_CBUF_FLIP, 1)
        await RisingEdge(dut.cbuf_transferred)

        assert (await self.lb.read(self.P_ADDR_CBUF_READY)).value.to_unsigned()
        dut.lb_read.value = 1
        wfm = []
        n_samples = (1 << self.CBUF_AW) // self.cic_n_chan // 2
        for idx in range(n_samples):
            offset = self.cic_n_chan * idx * 2 + self.P_ADDR_CBUF_DATA_BASE
            rdata = await self.lb.read(offset + chan * 2)
            i = rdata.value.to_signed()
            rdata = await self.lb.read(offset + chan * 2 + 1)
            q = rdata.value.to_signed()
            wfm.append(i + 1j * q)

        dut.lb_addr.value = 0
        dut.lb_read.value = 0
        return np.array(wfm, dtype=np.complex64)

    def check_sig(self, sig_meas, sig_name='signal', amp_exp=0, phs_exp=0):
        """Check the measured signal against expected amplitude and phase."""
        amp_meas = np.abs(sig_meas)
        phs_meas = np.angle(sig_meas, deg=True)
        cocotb.log.warning(
            f"expected {sig_name:12s} mag: {amp_exp:8.2f} cnt,  "
            f"phs: {phs_exp:6.3f} deg")
        cocotb.log.warning(
            f"measured {sig_name:12s} mag: {amp_meas:8.2f} cnt,  "
            f"phs: {phs_meas:6.3f} deg")
        amp_err = abs(amp_meas - amp_exp) / amp_exp
        assert amp_err < 0.001, "amplitude out-of-bound of 0.1%"
        phs_err = abs(wrap_phase(phs_meas - phs_exp))
        assert phs_err < 0.1, "phase out-of-bound of 0.1 deg"


@cocotb.test(timeout_time=200, timeout_unit='us')
@cocotb.parametrize(
    trig_sel=['WAVE_TRIG_ALWAYS', 'WAVE_TRIG_INT']
)
async def test_cic_waves_capture(dut, trig_sel='WAVE_TRIG_ALWAYS'):
    tb = TB(dut)
    await tb.reset()
    await tb.configure()
    await tb.set_wave_trig_sel(trig_sel)
    await tb.pulse_ext_trig()
    test_sig = 100 + 1j * 200
    await tb.stream_iq_data(i=test_sig.real, q=test_sig.imag)

    await tb.read_cic_waveform()  # discard first waveform
    cic_meas = await tb.read_cic_waveform()
    cic_meas = cic_meas[2:]  # XXX discard first 2 samples due to transient
    tb.check_sig(
        cic_meas.mean() / tb.cic_mon.gain, sig_name='chan0',
        amp_exp=np.abs(test_sig), phs_exp=np.angle(test_sig, deg=True))
