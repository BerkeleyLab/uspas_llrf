# A test of modbus-over-serial

import re
import os
from pymodbus.client import ModbusSerialClient, ModbusTcpClient
from pymodbus import FramerType

"""
picorv32 supported function codes:
    MODBUS_READ_HOLDING_REGISTERS     3
    MODBUS_PRESET_SINGLE_REGISTER     6
    MODBUS_PRESET_MULTIPLE_REGISTERS 16
Function Codes sent by MOXA
  0x83?
  0x90?
"""

# Test Modbus RTU through MOXA Serial Ethernet Adapter
# Connect MOXA adapter (NPort 5000 series) ethernet, which has default IP address of `192.168.127.254`.
# username: admin
# password: moxa
# 1. Set static IP address to `192.168.127.254`
# 2. Select "TCP" option without "Device is TCP client"
# 3. Set serial settings to be 115200 / 8 / N / 1, with RS-485 2-wire interface.
#
# Make hardware connections for half duplex:
# * Wire digilent PMOD 485 A to Y, B to Z;
# * Wire MOXA D+ to R+, D- to R-;
# * Wire PMOD 485 A to MOXA D+, B to D-;


def get_exception_str(mb_exception):
    mb_exception_dict = {
        1: "ILLEGAL_FUNCTION",
        2: "ILLEGAL_ADDRESS",
        3: "ILLEGAL_VALUE",
        4: "DEVICE_FAILURE",
        5: "ACKNOWLEDGE",
        6: "DEVICE_BUSY",
        8: "MEMORY_PARITY_ERR",
    }
    return mb_exception_dict.get(mb_exception)


def _isIP(ss):
    rs = r"^\d{1,3}.\d{1,3}.\d{1,3}.\d{1,3}$"
    if re.match(rs, ss):
        return True
    return False


def test__isIP():
    ll = (
        ("192.168.1.1", True),
        ("192.168.1.x", False),
        ("1.1.1.1", True),
        ("x.1.1.1", False),
        ("10.10.100.255", True),
    )
    fail = False
    for ip, expected in ll:
        rval = _isIP(ip)
        if rval != expected:
            print(f"Failed on {ip}. Expected {expected}, got {rval}")
            fail = True
    if fail:
        return 1
    return 0


def _isTTY(ss):
    dpath, dev = os.path.split(ss)
    if dev.startswith("tty"):
        return True
    return False


def getClient(ss=None):
    if ss is None:
        devstr = "192.168.127.254"
    else:
        devstr = ss
    if _isIP(devstr):
        # client = ModbusTcpClient(devstr, port=4001, framer=ModbusRtuFramer)
        # client = ModbusTcpClient(devstr, port=4001)
        # client = ModbusTcpClient(devstr, port=4001, framer=FramerRTU)
        client = ModbusTcpClient(devstr, port=4001, framer=FramerType.RTU)
    elif _isTTY(devstr):
        client = ModbusSerialClient(devstr, baudrate=115200, framer=FramerType.RTU)
    else:
        raise Exception(f"Cannot interpret device string {devstr}. Please provide a serial/TTY "
                        "(e.g. \"/dev/ttyUSB0\") or an IPv4 address (e.g. 192.168.127.254).")
    return client


def main():
    import sys
    if len(sys.argv) < 2:
        devstr = "192.168.127.254"
    else:
        devstr = sys.argv[1]
        if devstr.strip().lower() in ("-h", "--help"):
            print(f"{sys.argv[0]} (ttyport|ip_addr)")
            return 1
    client = getClient(devstr)
    _pass = True
    _test_pass = True

    # Check implemented function codes
    print(f"Connecting to {devstr}...")
    client.connect()
    addr = 0
    value = 1
    values = [3, 4]
    print("==== Testing MODBUS_READ_HOLDING_REGISTERS ====")
    val = client.read_holding_registers(addr, count=1)  # function code 3
    print(f"  Read from {addr} = {val.registers}")
    print("  PASS")
    print("==== Testing MODBUS_PRESET_SINGLE_REGISTER ====")
    client.write_register(addr, value)  # function code 6
    print(f"  Write {value} to {addr}")
    val = client.read_holding_registers(addr, count=1)  # function code 3
    print(f"  Read from {addr} = {val.registers}")
    if val.registers[0] == value:
        print("  PASS")
    else:
        print("  FAIL")
        _pass = False
    print("==== Testing MODBUS_PRESET_MULTIPLE_REGISTERS ====")
    client.write_registers(addr, values)  # function code 16 (0x10)
    print(f"  Write {values} starting from {addr}")
    val = client.read_holding_registers(addr, count=len(values))
    print(f"  Read from {addr} = {val.registers}")
    for n in range(len(val.registers)):
        if val.registers[n] != values[n]:
            _test_pass = False
            _pass = False
    if _test_pass:
        print("  PASS")
    else:
        print("  FAIL")

    client.close()
    if _pass:
        return 0
    else:
        return 1
    return 0


if __name__ == "__main__":
    exit(main())
    # exit(test__isIP())
