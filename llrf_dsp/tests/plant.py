import cocotb
from cocotb.queue import Queue
from cocotb.triggers import Timer
from typing import Optional
from abc import ABC, abstractmethod


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
    def gain(self, val: float) -> None:
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


class ADC(Element):
    def __init__(self,
                 n_bits: int = 16,
                 ref_val_V: float = 1.0,
                 delay_ns: float = 0.1,
                 i_queue: Optional[Queue] = None,
                 o_queue: Optional[Queue] = None) -> None:
        self.ref_val_V = ref_val_V
        self.n_bits = n_bits
        self.min_val = -(1 << (n_bits - 1))
        self.max_val = (1 << (n_bits - 1)) - 1
        super().__init__(delay_ns, i_queue, o_queue)

    def step(self, in_val):
        out = int(in_val * 2**self.n_bits / self.ref_val_V)
        assert self.min_val <= out <= self.max_val, \
            f"ADC saturation: in_val={in_val}"
        return out


class DAC(Element):
    def __init__(self,
                 n_bits: int = 16,
                 ref_val_V: float = 1.0,
                 delay_ns: float = 0.1,
                 i_queue: Optional[Queue] = None,
                 o_queue: Optional[Queue] = None) -> None:
        self.ref_val_V = ref_val_V
        self.n_bits = n_bits
        self.min_val = -(1 << (n_bits - 1))
        self.max_val = (1 << (n_bits - 1)) - 1
        super().__init__(delay_ns, i_queue, o_queue)

    def step(self, in_val):
        assert self.min_val <= in_val <= self.max_val, \
            f"DAC saturation: in_val={in_val}"
        out = in_val / 2**self.n_bits * self.ref_val_V
        return out


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

    def __init__(self, Q: float = 1.0,
                 delay_ns: float = 0.1,
                 i_queue: Optional[Queue] = None,
                 o_queue: Optional[Queue] = None, ) -> None:
        self._Q = Q
        super().__init__(delay_ns, i_queue, o_queue)

    @property
    def Q(self) -> float:
        return self._Q

    def step(self, in_val):
        return in_val * 1


class Plant:
    """Model of an RF plant including DAC, HPA, cavity, ADC
    """
    def __init__(self) -> None:
        self.i_queue = Queue()
        self.o_queue = Queue()
        self.q = [Queue()] * 3
        self.dac = DAC(i_queue=self.i_queue, o_queue=self.q[0])
        self.hpa = HPA(i_queue=self.q[0], o_queue=self.q[1])
        self.cav = CAV(i_queue=self.q[1], o_queue=self.q[2])
        self.adc = ADC(i_queue=self.q[2], o_queue=self.o_queue)


class PlantSimple:
    """Model of an RF plant including HPA, cavity
    """
    def __init__(self) -> None:
        self.i_queue = Queue()
        self.o_queue = Queue()
        self.q = Queue()
        self.hpa = HPA(i_queue=self.i_queue, o_queue=self.q)
        self.cav = CAV(i_queue=self.q, o_queue=self.o_queue)
