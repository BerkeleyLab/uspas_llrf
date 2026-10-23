"""LEMP register map: the base map with 1K signal buffers (D1) and the
iq_buf window over all 20 I/Q buffers, read in one call (addr_width 15)."""

SIG_BUF_AW = 10


def aliases(rm, m):
    i_base = next(b.base for b in m.blocks if b.name == 'adc0_i_buf')
    return [rm.Alias('iq_buf', i_base, 15, 18, signed=True,
                     description='adc0..7, drv0..1 I then Q buffers, one read')]
