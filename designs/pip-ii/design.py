"""pip-ii register map: the base map plus pulse modulation (lut0/1)."""


def design(rm):
    regs = rm.base_regs()
    rm.insert_after(regs, 'loop1_pulse_high_len',
                    [rm.Reg('lut0_len', 16), rm.Reg('lut1_len', 16)])
    rm.insert_after(regs, 'drv1_pulse_mode',
                    [rm.Reg('pulse_res_shift', 4), rm.Reg('pulse_modulation_enable', 2)])
    return regs
