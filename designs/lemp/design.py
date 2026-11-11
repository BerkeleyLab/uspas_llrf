"""LEMP register map (plan step 9c): the base map with 1K signal buffers
(D1), the iq_buf window over all 20 I/Q buffers (addr_width 15), and the
LEMP shell's registers and status words. Names are the LEMP branch's;
addresses come from the allocator (D24)."""

SIG_BUF_AW = 10
N_TRIG = 4  # PMOD triggers

# base registers the LEMP shell has no use for: timing_core_local has no
# event code or OC decoder (plan 9c, B3)
DROPPED = ['evcode', 'evr_oc_delay']


def design(rm):
    regs = [r for r in rm.base_regs() if r.name not in DROPPED]
    regs += [
        # phase step added to loop n's phase setpoint from pulse_start +
        # loopN_phs_shift_delay to the pulse end (dsp clocks)
        *[r for n in range(rm.N_DRIVE) for r in (
            rm.Reg(f'loop{n}_phs_shift', 18, signed=True),
            rm.Reg(f'loop{n}_phs_shift_delay', 32))],
        # EVR trigger (wave_trig_sel EVR): accelerate or standby after each fiducial.
        # The trigger registers boot at 0 (EVR trigger and PMOD triggers off), so
        # a reboot returns to that; software sets the operating values.
        rm.Reg('event_sel', 8, init=0, description='151: accelerate (falls back to standby), 152: standby'),
        rm.Reg('trig_acc_delay', 32, init=0, description='EVR trigger delay in accelerate (dsp clocks)'),
        rm.Reg('trig_stb_delay', 32, init=0, description='EVR trigger delay in standby (dsp clocks)'),
        rm.Reg('trig_enables', N_TRIG, init=0),
        *[rm.Reg(f'trig_{k}_{p}', 32, init=0, inst='trig', index=k) for k in range(N_TRIG)
          for p in ('width', 'delay')],
        rm.Reg('sssb_rf_switch'),
        rm.Reg('sssb_rst'),
    ]
    return regs


def status(rm):
    drop = {'evr_hb_valid', 'evr_pps_valid', 'evr_oc_valid', 'evr_oc_frequency'}
    st = [s for s in rm.base_status() if s.name not in drop]
    for s in st:
        if s.name == 'evr_evcnt':
            s.width = 16  # timing_core_local
    return rm.place_status(st, [
        ('dsp_clk_frequency', 28), ('sssb_alarm', 1), ('sssb_rf_status', 1),
        *[(f'evr_frequency_event{k}', 28) for k in range(1, 5)],
        ('acc_cycles', 28), ('stb_cycles', 28)])


def aliases(rm, m):
    i_base = next(b.base for b in m.blocks if b.name == 'adc0_i_buf')
    return [rm.Alias('iq_buf', i_base, 15, 18, signed=True,
                     description='adc0..7, drv0..1 I then Q buffers, one read'),
            # slow_bridge fields after dsp_slow_adc_max, named as on the LEMP branch
            rm.Alias('dsp_slow_evr_seconds_0', 0x10926, 0, 16),
            rm.Alias('dsp_slow_evr_seconds_1', 0x10927, 0, 16),
            rm.Alias('dsp_slow_evr_evticks_0', 0x10928, 0, 16),
            rm.Alias('dsp_slow_evr_evticks_1', 0x10929, 0, 16),
            rm.Alias('dsp_slow_timestamp', 0x1092a, 0, 16)]


# Intended differences from the LEMP-branch map (_baseline/llrf_shell.json,
# 2e25cd9), on top of regmap.RENAMES/ADDITIONS/REMOVALS/WIDTH_CHANGES; checked
# by test_regmap_compat (plan step 9c)
COMPAT_REMOVALS = [*DROPPED, 'trig_rsts_p', 'evr_sync_status',  # B3, L3, B2
                   'fiducial_sel']  # one master trigger: wave_trig_sel EVR (LEMP review)
COMPAT_ADDITIONS = ['fault_amp']  # main since the LEMP branch split
COMPAT_CHANGES = {  # name: (data_width, sign)
    **{f'loop{n}_phs_shift': (18, 'signed') for n in range(2)},  # 18-bit phase (was 32, low 18 used)
    'stb_cycles': (28, 'unsigned'),  # B4: the counter is 28 bits
    'sssb_alarm': (1, 'unsigned'),
    'sssb_rf_status': (1, 'unsigned'),
}
