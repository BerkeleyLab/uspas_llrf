from cocotb_bus.drivers import BusDriver
from cocotb_bus.monitors import BusMonitor
from cocotb.triggers import RisingEdge, ClockCycles
import json
from pathlib import Path
from dataclasses import dataclass


@dataclass
class Register:
    access: str = 'rw'
    addr_width: int = 0
    data_width: int = 32
    base_addr: int = 0
    description: str = ''
    sign: str = 'unsigned'


class RegisterMap:
    def __init__(self, json_path='../../llrf_shell.json'):
        assert Path(json_path).exists(), \
            f"Register map file {json_path} does not exist."
        with open(json_path, 'r') as f:
            self._reg_map = json.load(f)
        for name, reg in self._reg_map.items():
            setattr(self, name, Register(**reg))


class LocalBusMaster(BusDriver):
    _signals = ['read', 'write', 'addr', 'wdata', 'rdata', 'rvalid']

    def __init__(self, entity, clock, name='lb', read_latency=3, **kwargs):
        self._read_latency = read_latency
        super().__init__(entity, name, clock, **kwargs)

    async def write(self, addr, data):
        """Write data to the bus at the specified address."""
        await RisingEdge(self.clock)
        self.bus.write.value = 1
        self.bus.addr.value = addr
        self.bus.wdata.value = data
        await RisingEdge(self.clock)
        self.bus.write.value = 0

    async def read(self, addr):
        """Read data from the bus at the specified address."""
        await RisingEdge(self.clock)
        self.bus.read.value = 1
        self.bus.addr.value = addr
        await ClockCycles(self.clock, self._read_latency)
        self.bus.rvalid.value = 1
        await RisingEdge(self.clock)
        data = self.bus.rdata.value
        self.bus.rvalid.value = 0
        self.bus.read.value = 0
        return data


class LocalBusMonitor(BusMonitor):
    _signals = ['read', 'write', 'addr', 'wdata', 'rdata', 'rvalid']

    async def _monitor_recv(self):
        """Watch the pins and reconstruct transactions."""

        while True:
            await RisingEdge(self.clock)
            if str(self.bus.rvalid.value) == '1':
                self._recv(int(self.bus.rdata.value))


class LocalbusAppMaster(LocalBusMaster):
    def __init__(self, entity, clock, name='lb', read_latency=3,
                 regmap_json_path='../../llrf_shell.json', **kwargs):
        self.reg_map = RegisterMap(regmap_json_path)
        super().__init__(entity, clock, name, read_latency, **kwargs)

    async def write_reg(self, reg_name, data):
        """Write data to a register by name."""
        reg = getattr(self.reg_map, reg_name, None)
        if reg is None:
            raise ValueError(f"Register {reg_name} not found in register map.")
        if reg.access not in ['rw', 'w']:
            raise ValueError(f"Register {reg_name} is not writable.")
        addr = reg.base_addr
        await self.write(addr, data)

    async def read_reg(self, reg_name):
        """Read data from a register by name."""
        reg = getattr(self.reg_map, reg_name, None)
        if reg is None:
            raise ValueError(f"Register {reg_name} not found in register map.")
        addr = reg.base_addr
        if reg.access not in ['rw', 'r']:
            raise ValueError(f"Register {reg_name} is not readable.")
        data = await self.read(addr)
        if reg.sign == 'signed':
            return data.signed_integer
        else:
            return data.integer
