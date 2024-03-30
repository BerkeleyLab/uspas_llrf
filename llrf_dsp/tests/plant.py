import cocotb
from cocotb.queue import Queue
from typing import Optional


class HPA:
    """
    Model of a High power Amplifier.
    """

    def __init__(
        self,
        gain: float = 1.0,
        i_queue: Optional[Queue] = None,
        o_queue: Optional[Queue] = None,
    ) -> None:
        self._gain = gain
        self.i_queue = i_queue
        self.o_queue = o_queue
        cocotb.start_soon(self.run())

    @property
    def gain(self) -> float:
        return self._gain

    @gain.setter
    def gain(self, val: float) -> None:
        self._gain = val

    async def run(self) -> None:
        while True:
            in_val = await self.i_queue.get()
            await self.o_queue.put(in_val * self._gain)


class Cavity:
    """
    Model of a RF cavity.
    TBD: add equation
    """

    def __init__(
        self,
        Q: float = 1.0,
        i_queue: Optional[Queue] = None,
        o_queue: Optional[Queue] = None,
    ) -> None:
        self._Q = Q
        self.i_queue = i_queue
        self.o_queue = o_queue
        cocotb.start_soon(self.run())

    @property
    def Q(self) -> float:
        return self._Q

    async def run(self) -> None:
        while True:
            in_val = await self.i_queue.get()
            await self.o_queue.put(in_val)


class Plant:
    """Model of an RF plant including cable, HPA, cavity
    """
    def __init__(self, hpa_gain=1.0) -> None:
        self.i_queue = Queue()
        self.o_queue = Queue()
        self.q = Queue()
        self.hpa = HPA(i_queue=self.i_queue, o_queue=self.q, gain=hpa_gain)
        self.cav = Cavity(i_queue=self.q, o_queue=self.o_queue)
