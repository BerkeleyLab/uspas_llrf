"""dds.v with DWH 32, loop_ctrl's sinusoidal modulation (plan step 13, D32):
the CW excitation for measuring a loop's transfer function.

The phase is checked bit-exact on every clock against a model of
ph_acc_general, which pins the frequency for both kinds of phase step:
an exact num/den of the sample rate (non-binary, modulo != 0) and a binary
44-bit step for any frequency (modulo 0, dds_config_for_freq). The CORDIC
outputs are checked against the amplitude and the phase, and the phase
accumulator restarts on the reset input (dsp_reset in loop_ctrl, the
trigger in rx/tx-style uses).
"""
import logging
import random

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge

from uspas_llrf import DDS, dds_config_for_freq

F_S = 114.67375e6  # nominal dsp_clk (uspas), only to name frequencies


class PhaseAcc:
    """Clock-by-clock model of ph_acc_general.v (DWO output bits)."""
    def __init__(self, dwh, dwl, dwo):
        self.dwh, self.dwl, self.dwo = dwh, dwl, dwo
        self.carry = self.phase_l = self.phase_h = self.step_hp = self.reset1 = 0

    def clock(self, reset, step_h, step_l, modulo):
        if reset or self.reset1:
            self.carry = self.phase_l = self.phase_h = self.step_hp = 0
        else:
            low = (modulo if self.carry else 0) + self.phase_l + step_l
            self.phase_h = (self.phase_h + self.step_hp + self.carry) % (1 << self.dwh)
            self.carry, self.phase_l = low >> self.dwl, low & ((1 << self.dwl) - 1)
            self.step_hp = step_h
        self.reset1 = reset

    @property
    def phase(self):
        return self.phase_h >> (self.dwh - self.dwo)


class TB:
    def __init__(self, dut):
        dut._log.setLevel(logging.INFO)
        self.dut = dut
        self.dwlo = dut.DWLO.value.to_unsigned()
        self.dwh = dut.DWH.value.to_unsigned()
        self.dwl = dut.DWL.value.to_unsigned()
        assert self.dwh == 32, "loop_ctrl's dds has DWH 32"
        self.acc = PhaseAcc(self.dwh, self.dwl, self.dwlo + 1)
        self.regs = (0, 0, 0)
        self.reset = 0
        self.log = []  # (phase_out, cos_out, sin_out) per clock
        cocotb.start_soon(Clock(dut.clk, 8, unit="ns").start())
        dut.reset.value = 0
        dut.phase_shift.value = 0  # tied to 0 in the shells
        self.set_regs(0, 0, 0, 0)

    def set_regs(self, amp, step_h, step_l, modulo):
        self.dut.amplitude.value = amp
        self.dut.phase_step_h.value = step_h
        self.dut.phase_step_l.value = step_l
        self.dut.modulo.value = modulo
        self.regs = (step_h, step_l, modulo)

    async def run(self, n, reset_at=()):
        """n clocks; the model follows each rising edge, and the outputs are
        compared on the falling edge after it. reset_at: clocks (counted
        from 0 in this call) with the reset input high for one cycle."""
        for k in range(n):
            self.reset = int(k in reset_at)
            self.dut.reset.value = self.reset
            await RisingEdge(self.dut.clk)
            self.acc.clock(self.reset, *self.regs)
            await FallingEdge(self.dut.clk)
            phase = self.dut.phase_out.value.to_unsigned()
            assert phase == self.acc.phase, \
                f"clock {k}: phase_out {phase:#07x}, model {self.acc.phase:#07x}"
            self.log.append((phase, self.dut.cos_out.value.to_signed(),
                             self.dut.sin_out.value.to_signed()))

    def check_cordic(self, model, n):
        """cos_out + j sin_out against the amplitude and the phase of the
        last n clocks, at the CORDIC latency (found, then checked)."""
        amp_exp = abs(model.gain) * (1 << self.dwlo - 1)
        log = np.array(self.log[-n:])
        theta = log[:, 0] * 2 * np.pi / (1 << self.dwlo + 1)
        iq = log[:, 1] + 1j * log[:, 2]

        def err(lag):
            return np.max(np.abs(iq[lag:] - amp_exp * np.exp(1j * theta[:n - lag])))
        lag = min(range(40), key=err)
        cocotb.log.info(f"CORDIC latency {lag} clocks, max error {err(lag):.2f} "
                        f"counts at amplitude {amp_exp:.1f}")
        # phase_out leaves the accumulator register, one clock after the
        # input the model's CORDIC_LATENCY counts from
        assert lag == model.CORDIC_LATENCY - 1, f"latency {lag}, model {model.CORDIC_LATENCY} - 1"
        assert err(lag) < 1e-3 * amp_exp, "CORDIC output off by more than 0.1% of the amplitude"


async def check_config(dut, regs, model, n=3000):
    tb = TB(dut)
    tb.set_regs(model.amp, *regs)
    await tb.run(n, reset_at=(0,))  # the DUT keeps its state between tests
    tb.check_cordic(model, n - 100)
    return tb


def amp_model(num=1, den=1, rng=random):
    m = DDS(num=num, den=den, dwh=32, dwl=12)
    m.amp = int(rng.uniform(0.8, 0.95) * m.full_scale_amp)
    return m


@cocotb.test()
async def test_exact_fraction(dut):
    """num/den of the sample rate with den up to 2**DWL: the phase step's
    non-binary part (modulo != 0) makes the frequency exact."""
    for num, den in [(7, 33), (1, 4093)]:
        m = amp_model(num, den)
        regs = m.calc_dds_config(dwh=32, dwl=12)
        assert regs[2] != 0
        cocotb.log.info(f"{num}/{den}: phase_step_h {regs[0]:#x}, l {regs[1]:#x}, modulo {regs[2]}")
        tb = await check_config(dut, regs, m, n=max(3000, 2 * den + 100))
        # exact: the phase repeats every den clocks (after the restart)
        phase = [p for p, _, _ in tb.log]
        assert all(phase[k + den] == phase[k] for k in range(10, len(phase) - den)), \
            f"{num}/{den}: phase not periodic in {den} clocks"


@cocotb.test()
async def test_any_frequency(dut):
    """An excitation frequency (150 kHz + 0.01 Hz at the uspas rate)
    as a binary 44-bit step: dds_config_for_freq, modulo 0, resolution
    F_S / 2**44 (6.5 uHz). The rx/tx layout (20 + 12 bits) would resolve
    F_S / 2**32 (0.027 Hz) used the same way."""
    freq = 150e3 + 0.01
    regs = dds_config_for_freq(freq, F_S)
    assert regs[2] == 0
    step = (regs[0] << 12) | regs[1]
    assert abs(step / 2**44 * F_S - freq) <= F_S / 2**45
    assert regs != dds_config_for_freq(150e3, F_S)
    await check_config(dut, regs, amp_model())


@cocotb.test()
async def test_trigger_restart(dut):
    """The reset input restarts the phase:
    0 for the two clocks the accumulator holds reset, then the same
    sequence as after the first reset, wherever the trigger falls."""
    m = amp_model(7, 33)
    regs = m.calc_dds_config(dwh=32, dwl=12)
    tb = TB(dut)
    tb.set_regs(m.amp, *regs)
    n, resets = 400, (5, 137, 290)
    await tb.run(n, reset_at=(0,) + resets)
    phase = [p for p, _, _ in tb.log]
    span = min(b - a for a, b in zip(resets, resets[1:] + (n,)))
    for r in resets:
        assert phase[r] == 0 and phase[r + 1] == 0, f"phase not held at 0 after the reset at {r}"
        assert phase[r:r + span] == phase[resets[0]:resets[0] + span], \
            f"sequence after the reset at {r} differs from the first"
    assert len(set(phase[resets[0]:resets[0] + span])) >= 33  # it advances (7/33: 33 phases)
