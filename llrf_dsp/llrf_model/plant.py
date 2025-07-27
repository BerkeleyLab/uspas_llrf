import json
import numpy as np
from scipy import signal
from .llrf_dsp import LLRFModel
import cocotb
from cocotb.queue import Queue
from cocotb.triggers import Timer
from typing import Optional
from abc import ABC, abstractmethod
from importlib.resources import files


class Element(ABC):
    """General RF element
    """
    def __init__(
        self,
        delay_ns: float = 0.1,
        i_queue: Optional[Queue] = None,
        o_queue: Optional[Queue] = None,
    ) -> None:
        self._delay = delay_ns
        self.i_queue = i_queue
        self.o_queue = o_queue
        cocotb.start_soon(self.run())

    @property
    def delay(self) -> float:
        return self._delay

    @delay.setter
    def delay(self, val: float) -> None:
        self._delay = val

    @abstractmethod
    def step(self, in_val):
        return

    async def run(self) -> None:
        while True:
            in_val = await self.i_queue.get()
            await Timer(self.delay, 'ns')
            out_val = self.step(in_val)
            await self.o_queue.put(out_val)


class HPA(Element):
    """
    Model of a High power Amplifier.
    """

    def __init__(self, gain: float = 1.0,
                 delay_ns: float = 0.1,
                 i_queue: Optional[Queue] = None,
                 o_queue: Optional[Queue] = None) -> None:
        self._gain = gain
        super().__init__(delay_ns, i_queue, o_queue)

    @property
    def gain(self) -> float:
        return self._gain

    @gain.setter
    def gain(self, val: float) -> None:
        self._gain = val

    def step(self, in_val):
        return in_val * self.gain


class CAV(Element):
    """
    Model of a RF cavity.
    TBD: add equation
    """

    def __init__(self,
                 delay_ns: float = 0.1,
                 conf='LEMP', settings_fname='cavity.json',
                 llrf: LLRFModel = LLRFModel(),
                 i_queue: Optional[Queue] = None,
                 o_queue: Optional[Queue] = None, ) -> None:
        f_path = files('llrf_model').joinpath(settings_fname)
        with open(f_path) as f:
            configs = json.load(f)
        for k, v in configs[conf].items():
            setattr(self, k, v)
        super().__init__(delay_ns, i_queue, o_queue)

        self.conf = conf
        self.Ql = self.Q0 / (1 + self.beta)
        self.alpha = np.pi * self.f0 / self.Ql

        self.fs = 1e9 / llrf.DSP_CLK_CYCLE
        self.f_if = llrf.NUM_DDS / llrf.DEN_DDS * self.fs

        self.system_z = self.create_sys_z()

        self.zi = np.zeros(len(self.system_z.den) - 1)

    def create_sys_z(self):
        """Model cavity in IF frequency as an IIR digital filter. See lit.ipynb

        Returns:
           scipy.signal._ltisys.TransferFunctionDiscrete : digital system
        """
        T = 1 / self.fs
        B = 2 * self.alpha  # bandwidth in rad/s
        omega_0 = 2 * np.pi * self.f_if  # center frequency in rad / s
        omega_norm = omega_0 / self.fs

        # Prewarp the center frequency omega_0
        omega_0_warped = 2 * self.fs * np.tan(omega_0 / (2 * self.fs))
        B_warped = B * omega_0_warped / omega_0

        # compensate bilinear transform bandwidth
        B_warped /= np.sin(omega_norm) / omega_norm

        # Create the Transfer Function in the s-domain
        # with Pre-warped Parameters
        # Numerator [B_warped * s^1, B_warped * s^0]
        num = [B_warped, 0]
        # Denominator [s^2, B_warped * s^1, omega_0_warped^2]
        den = [1, B_warped, omega_0_warped**2]

        # Convert the transfer function from s-domain to z-domain
        #  using bilinear transform
        num_z, den_z = signal.bilinear(num, den, fs=self.fs)

        # Create the discrete-time transfer function
        system_z = signal.TransferFunction(num_z, den_z, dt=T)
        return system_z

    def __repr__(self):
        str = (
            f'Config:        {self.conf:>8s}\n'
            f'Q_L:           {self.Ql:8.1f}\n'
            f'Center freq:   {self.f0 / 1e6:8.1f} MHz\n'
            f'half bandwidth:{self.alpha / 2e3 / np.pi:8.1f} kHz\n'
            f'F_if:          {self.f_if / 1e6:8.1f} MHz\n'
            f'F_adc:         {self.fs / 1e6:8.1f} MHz\n'
            f'system_z:      {self.system_z}')
        return str

    def step(self, in_val):
        """ simulate the cavity response as an IIR filter,
            sample by sample"""
        y, self.zi = signal.lfilter(
            self.system_z.num, self.system_z.den, x=[in_val], zi=self.zi)
        return y[0]


class Plant:
    """Model of an RF plant including HPA, cavity
    """
    def __init__(self,
                 conf='LEMP', settings_fname='cavity.json',
                 llrf: LLRFModel = LLRFModel(),
                 ) -> None:
        self.i_queue = Queue()
        self.o_queue = Queue()
        self.q = Queue()
        self.hpa = HPA(
            i_queue=self.i_queue, o_queue=self.q,
            gain=10, delay_ns=3)
        self.cav = CAV(
            conf=conf, settings_fname=settings_fname, llrf=llrf, delay_ns=2,
            i_queue=self.q, o_queue=self.o_queue)
