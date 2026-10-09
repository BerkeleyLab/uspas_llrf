# A test of reading/writing LLRF registers via modbus-over-serial

from modbus_test import getClient, get_exception_str
from pymodbus.pdu.register_message import ReadHoldingRegistersResponse
from pymodbus.pdu.pdu import ExceptionResponse
from leep import open as LEEPOpen
import random
import tomllib


VERBOSE = False
REPORT_SUCCESS = False


"""
picorv32 supported function codes:
    MODBUS_READ_HOLDING_REGISTERS     3
    MODBUS_PRESET_SINGLE_REGISTER     6
    MODBUS_PRESET_MULTIPLE_REGISTERS 16
"""


global mb_addr_map
mb_addr_map = None


def get_addr_map(filepath):
    with open(filepath, 'rb') as fd:
        _map = tomllib.load(fd)
    return _map


class ModbusAddrMap():
    INDEX_MB_NAME = 0
    INDEX_LEEP_NAME = 1
    INDEX_OFFSET = 2
    INDEX_WRITEABLE = 3
    INDEX_ISWORD = 4

    def __init__(self, filepath):
        self._toml_file = filepath
        self.get_leep_map(filepath)

    def get_leep_map(self, filepath):
        _map = get_addr_map(filepath)
        ro = _map.get("ro", {})
        rw = _map.get("rw", {})
        sp = _map.get("sp", {})
        # NOTE! It's important to do these in the same order as modbusAddrMap.py
        order = (ro, rw, sp)
        address = 0
        addrs = {}
        self._strings = []
        for dd in order:
            for mb_postfix, leep_data in dd.items():
                mb_name = f"MB_{mb_postfix.upper()}"
                isword = leep_data[2]
                offset = leep_data[1]
                leep_name = leep_data[0]
                self._strings.append(mb_name)
                if dd == rw:
                    _writeable = True
                else:
                    _writeable = False
                # See self.INDEX_*
                addrs[address] = (mb_name, leep_name, offset, _writeable, isword)
                if isword:
                    # Reserve the next address for the _HI value
                    address += 2
                else:
                    address += 1
        self._mb_dict = addrs
        return

    def get_leep_reg(self, mb_addr: int):
        """Returns (str leep_reg_name, int offset) for a given modbus address 'int mb_addr'"""
        data = self._mb_dict.get(mb_addr, None)
        if data is None:
            return (None, None)
        return (data[self.INDEX_LEEP_NAME], data[self.INDEX_OFFSET])

    def is_writable(self, mb_addr: int) -> bool:
        data = self._mb_dict.get(mb_addr, None)
        if data is None:
            return False
        return data[self.INDEX_WRITEABLE]

    def is_word(self, mb_addr: int) -> bool:
        data = self._mb_dict.get(mb_addr, None)
        if data is None:
            return False
        return data[self.INDEX_ISWORD]

    def get_all_rw(self):
        addrs = []
        for addr, data in self._mb_dict.items():
            if self.is_writable(addr):
                addrs.append(addr)
        return addrs


def get_data_max(mb_addr, leep_dev):
    default = 7
    if leep_dev is None:
        # We have no insight into data width, so let's just be conservative and test the low 3 bits
        return default
    leep_name, offset = mb_addr_map.get_leep_reg(mb_addr)
    reg_dict = leep_dev.regmap.get(leep_name, None)
    if reg_dict is None:
        print(f"WARNING: Could not find entry for {leep_name} in LEEP device's regmap")
        return default
    # Modbus can only handle 16 bits
    dw = reg_dict["data_width"]
    if dw > 16:
        print(f"Got a split register (dw = {dw}): {leep_name}")
    # Treat all regs as unsigned for value consistency
    return (1 << dw) - 1


def write(client, addr, val):
    if VERBOSE:
        print(f":: writing 0x{val:x} to 0x{addr:x}")
    if hasattr(client, "write_register"):
        # Assume modbus client
        if mb_addr_map.is_word(addr):
            # function code 16 (0x10)
            val = client.write_registers(addr, (val & 0xffff, (val >> 16) & 0xffff))
        else:
            # function code 6
            val = client.write_register(addr, val)
        if isinstance(val, ExceptionResponse):
            print(f"  ERROR: val.exception_code = {get_exception_str(val.exception_code)} ({val.exception_code})")
            val = None
    elif hasattr(client, "reg_write_offset"):
        # Assume leep client
        leep_name, offset = mb_addr_map.get_leep_reg(addr)
        if leep_name is None:
            raise Exception(f"No valid LEEP register associated with address {addr}")
        client.reg_write_offset(((leep_name, val, offset),))
    return


def read(client, addr):
    if VERBOSE:
        print(f":: Reading from 0x{addr:x}", end="")
    val = None
    if hasattr(client, "read_holding_registers"):
        # Assume modbus client
        if mb_addr_map.is_word(addr):
            val = client.read_holding_registers(addr, count=2)  # function code 3
        else:
            val = client.read_holding_registers(addr, count=1)  # function code 3
        if isinstance(val, ExceptionResponse):
            print(f"  ERROR: val.exception_code = {get_exception_str(val.exception_code)} ({val.exception_code})")
            val = None
        if isinstance(val, ReadHoldingRegistersResponse):
            if len(val.registers) == 1:
                val = val.registers[0]
            else:
                val = val.registers[0] | (val.registers[1] << 16)
    elif hasattr(client, "reg_read_size"):
        # Assume leep client
        leep_name, offset = mb_addr_map.get_leep_reg(addr)
        if leep_name is None:
            raise Exception(f"No valid LEEP register associated with address {addr}")
        vals = client.reg_read_size(((leep_name, 1, offset),))
        # Convert to unsigned
        dw = client.regmap[leep_name]["data_width"]
        mask = (1 << dw) - 1
        val = int(vals[0]) & mask
    if VERBOSE:
        if val is None:
            print(" val = None")
        else:
            print(f" val = 0x{val:x}")
    return val


def doTest(mb_client, leep_client):
    mb_client.connect()
    test_regs = mb_addr_map.get_all_rw()
    if leep_client is None:
        print(":: Testing modbus write and readback")
        phases = 1
    else:
        print(":: Testing modbus with OOB readback")
        phases = 2
    errors = 0
    for phase in range(phases):
        if leep_client is None:
            in_client = mb_client
            out_client = mb_client
        else:
            if phase == 0:
                print(":: Initial phase: Modbus write, LEEP read")
                in_client = leep_client
                out_client = mb_client
            else:
                print(":: Second phase: LEEP write, Modbus read")
                in_client = mb_client
                out_client = leep_client
        for mb_addr in test_regs:
            # Write with out_client
            high = get_data_max(mb_addr, leep_client)
            val = random.randint(0, high)
            write(out_client, mb_addr, val)
            # Read back with in_client
            rb_val = read(in_client, mb_addr)
            leep_name, offset = mb_addr_map.get_leep_reg(mb_addr)
            os = ""
            if offset > 0:
                os = f" (+{offset})"
            if rb_val != val:
                print(f"    ERROR: Wrote {val} to {leep_name}{os} (address {mb_addr}) "
                      f"via {out_client} and read {rb_val} from {in_client}")
                errors += 1
            else:
                if REPORT_SUCCESS:
                    print(f"    SUCCESS: Wrote {val} to {leep_name}{os} (address {mb_addr}) "
                          f"via {out_client} and read from {in_client}")
    mb_client.close()
    if errors == 0:
        print(f"PASS: {len(test_regs)} Checked.")
    else:
        print(f"FAIL: {errors}/{len(test_regs)} Errors.")
        return 1
    return 0


def doSpeedTest(mb_client, polling_period_ms):
    import time
    polling_period_ms = float(polling_period_ms)
    # interlock status (should not change over the run)
    addr = 30
    old_val = None
    for n in range(100):
        start = time.time()
        val = mb_client.read_holding_registers(addr, count=1)  # function code 3
        end = time.time()
        interval_ms = 1.0e3 * (end - start)
        if interval_ms > polling_period_ms:
            print(f"  !{interval_ms:.1f}")
        if isinstance(val, ReadHoldingRegistersResponse):
            if len(val.registers) == 1:
                val = val.registers[0]
            else:
                val = val.registers[0] | (val.registers[1] << 16)
        if old_val != val:
            old_val = val
            print(val)
        time.sleep(polling_period_ms * 1.0e-3)
    print("\nDONE")
    return


def main():
    import argparse
    parser = argparse.ArgumentParser("Modbus comms test with LEEP backdoor")
    parser.add_argument("toml_reg_map", help="Modbus-to-LEEP register map in TOML syntax.")
    parser.add_argument("-m", "--modbus_adapter", default=None,
                        help="\"192.168.127.254\" or \"/dev/ttyUSB0\"")
    parser.add_argument("-l", "--leep", default=None, help="LEEP descriptor (i.e. \"leep://192.168.19.48:803\")")
    parser.add_argument("-s", "--speed_test", default=None,
                        help="Run a speed test polling every SPEED_TEST milliseconds.")
    args = parser.parse_args()
    global mb_addr_map
    mb_addr_map = ModbusAddrMap(args.toml_reg_map)
    mb_client = getClient(args.modbus_adapter)
    if args.leep is not None:
        leep_client = LEEPOpen(args.leep)
    else:
        leep_client = None
        print("WARNING: Will not check modbus reads/writes via LEEP backdoor")
    if args.speed_test is not None:
        return doSpeedTest(mb_client, args.speed_test)
    return doTest(mb_client, leep_client)


if __name__ == "__main__":
    exit(main())
