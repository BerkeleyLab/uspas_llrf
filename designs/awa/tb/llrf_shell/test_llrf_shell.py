from uspas_llrf.tests.test_llrf_shell import TB_llrf_shell
import cocotb
import random


@cocotb.test(timeout_time=600, timeout_unit='us')
@cocotb.parametrize(
    amp_exp=[15000, 30000],
    phs_exp=[-100, 45, 270],
    loop=['loop0', 'loop1']
)
async def test(dut, amp_exp, phs_exp, loop):
    tb = TB_llrf_shell(
        dut,
        f_config='AWA',
        wave_samp_per=random.randint(1, 8),
        amp_exp=amp_exp, phs_exp=phs_exp,
        regmap_json_path='../../llrf_shell.json')
    await tb.test_open_loop(loop)
    await tb.test_fast_interlock(loop)
    await tb.test_close_loop(loop)
