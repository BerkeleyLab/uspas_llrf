from uspas_llrf import WaveTrigSel
from uspas_llrf.tests.test_llrf_shell import TB_llrf_shell
import cocotb
import random


@cocotb.test(timeout_time=600, timeout_unit='us')
@cocotb.parametrize(
    amp_exp=[15000, 30000],
    phs_exp=[-100, 45, 270],
)
async def test(dut, amp_exp, phs_exp, loop='loop0'):
    tb = TB_llrf_shell(
        dut,
        f_config='ALSU',
        wave_samp_per=random.randint(1, 8),
        amp_exp=amp_exp, phs_exp=phs_exp,
        regmap_json_path='../../llrf_shell.json')
    await tb.test_open_loop(loop)
    await tb.test_fast_interlock(loop)
    await tb.test_close_loop(loop)


@cocotb.test(timeout_time=600, timeout_unit='us')
@cocotb.parametrize(
    trig_sel=[WaveTrigSel.Always, WaveTrigSel.Internal]
)
async def test_cic_waves(dut, f_config='ALSU', amp_exp=15000, phs_exp=45,
                         trig_sel=WaveTrigSel.Always):
    tb = TB_llrf_shell(
        dut,
        f_config=f_config,
        wave_samp_per=random.randint(1, 8),
        amp_exp=amp_exp, phs_exp=phs_exp,
        regmap_json_path='../../llrf_shell.json')
    tb.log_banner('CIC waveform test')
    tb.llrf.init_regs.wave_trig_sel = trig_sel
    tb.llrf.init_regs.int_trigger_period = 3000
    await tb.write_init_regs()
    await tb.verify_init_regs()

    cocotb.log.warning(f'cic_wfm_gain: {tb.llrf.cic_wfm_gain:.3f}')
    # check phase reference adc only
    await tb.read_cic_waveform()  # flush buffer recorded across reconfiguration
    ch = 0 if tb.phaseref_adc < tb.loopback_adc else 1
    cic_meas = await tb.read_cic_waveform(ch)
    cic_meas = cic_meas[2:]  # XXX discard first 2 samples due to transient
    tb.check_sig(cic_meas.mean() / tb.llrf.cic_wfm_gain,
                 sig_name='phaseref_adc')
