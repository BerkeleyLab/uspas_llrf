'''
---------------------
 LiteX SoC on Marble
---------------------
with support for SO-DIMM DDR3, ethernet and UART.
To synthesize, add --build, to configure the FPGA over jtag, add --load.

-----------------
 Example configs
-----------------
with ethernet and DDR3, default IP: 192.168.1.70/24
  ./marble.py --with-ethernet --with-bist --spd-dump VR7PU286458FBAMJT.txt

lightweight config
  ./marble.py --integrated-main-ram-size 16384 --cpu-type serv

etherbone: access wishbone over ethernet
  ./marble.py --with-etherbone --csr-csv build/csr.csv

make sure reset is not asserted (RTS signal), set PC IP to 192.168.1.100/24,
then test and benchmark the etherbone link:
  cd build
  litex/liteeth/bench/test_etherbone.py --udp --ident --access --sram --speed
'''

from litex_boards.platforms import berkeleylab_marble
from migen import (Module, ClockDomain, Signal)
from litex.soc.cores.clock import (S7MMCM, S7IDELAYCTRL)
from litex.soc.integration.soc_core import SoCCore
from litex.soc.cores import bitbang, gpio, led
from litedram.modules import MT8JTF12864, parse_spd_hexdump, SDRAMModule
from litedram.phy import s7ddrphy
from liteeth.phy.s7rgmii import LiteEthPHYRGMII
from litespi.modules import S25FL128S
from litespi.opcodes import SpiNorFlashOpCodes as Codes


class _CRG(Module):
    def __init__(self, platform, sys_clk_freq):
        self.rst = Signal()
        self.clock_domains.cd_sys = ClockDomain()
        self.clock_domains.cd_sys4x = ClockDomain(reset_less=True)
        self.clock_domains.cd_sys4x_dqs = ClockDomain(reset_less=True)
        self.clock_domains.cd_idelay = ClockDomain()

        # # #

        self.submodules.pll = pll = S7MMCM(speedgrade=-2)

        self.comb += pll.reset.eq(self.rst)
        pll.register_clkin(platform.request("clk125"), 125e6)
        pll.create_clkout(self.cd_sys, sys_clk_freq)
        pll.create_clkout(self.cd_sys4x, 4 * sys_clk_freq)
        pll.create_clkout(self.cd_sys4x_dqs, 4 * sys_clk_freq, phase=90)
        pll.create_clkout(self.cd_idelay, 200e6)
        # Ignore sys_clk to pll.clkin path created by SoC's rst.
        platform.add_false_path_constraints(self.cd_sys.clk, pll.clkin)

        self.submodules.idelayctrl = S7IDELAYCTRL(self.cd_idelay)


class BaseSoC(SoCCore):
    def __init__(
            self, sys_clk_freq = int(125e6),
            with_ethernet = False, with_etherbone = False,
            eth_ip = "192.168.19.70", mac_address = 0x10e2d5012345,
            eth_dynamic_ip = False,
            with_spi_flash = False,
            with_led_chaser = True,
            spd_dump = None,
            **kwargs):
        platform = berkeleylab_marble.Platform()

        # SoCCore ---------------------------------------------------------------------------------
        SoCCore.__init__(
            self, platform, clk_freq=sys_clk_freq, ident="LiteX SoC on Marble v1.2", **kwargs)

        # CRG --------------------------------------------------------------------------------------
        self.submodules.crg = _CRG(platform, sys_clk_freq)

        # DDR3 SDRAM -------------------------------------------------------------------------------
        if not self.integrated_main_ram_size:
            self.submodules.ddrphy = s7ddrphy.K7DDRPHY(
                platform.request("ddram"),
                memtype = "DDR3",
                nphases = 4,
                sys_clk_freq = sys_clk_freq)

            if spd_dump is not None:
                ram_spd = parse_spd_hexdump(spd_dump)
                ram_module = SDRAMModule.from_spd_data(ram_spd, sys_clk_freq)
                print('DDR3: loaded config from', spd_dump)
            else:
                ram_module = MT8JTF12864(sys_clk_freq, "1:4")  # KC705 chip, 1 GB
                print('DDR3: No spd data specified, falling back to MT8JTF12864')

            self.add_sdram(
                name = "sdram",
                phy = self.ddrphy,
                module = ram_module,
                # size = kwargs.get("max_sdram_size", 0x40000000),  # limit to 1GB
                l2_cache_size = kwargs.get("l2_size", 8192),
                with_bist = kwargs.get("with_bist", False)
            )

        # SPI Flash -------------------------------------------------------------------------------
        if with_spi_flash:
            self.add_spi_flash(mode="1x", module=S25FL128S(Codes.READ_1_1_1), clk_freq=int(25e6))

        # Ethernet / Etherbone ---------------------------------------------------------------------
        if with_ethernet or with_etherbone:
            self.submodules.ethphy = LiteEthPHYRGMII(
                clock_pads=self.platform.request("eth_clocks"),
                pads=self.platform.request("eth"),
                tx_delay=1e-9)
            if with_ethernet:
                self.add_ethernet(phy=self.ethphy, dynamic_ip=eth_dynamic_ip)
            if with_etherbone:
                self.add_etherbone(phy=self.ethphy, ip_address=eth_ip, mac_address=mac_address)

        # I2C --------------------------------------------------------------------------------------
        i2c_pads = self.platform.request("i2c_fpga")
        self.submodules.i2c = bitbang.I2CMaster(i2c_pads)
        # self.submodules.i2c_reset = gpio.GPIOOut(
        #     self.platform.request("i2c_fpga_sw_rst"))

        # Leds -------------------------------------------------------------------------------------
        if with_led_chaser:
            self.submodules.leds = led.LedChaser(
                pads = platform.request_all("user_led"),
                sys_clk_freq = sys_clk_freq)

def main():
    import os
    import argparse
    from litex.soc.integration.soc_core import soc_core_argdict, soc_core_args
    from litex.soc.integration.builder import builder_args, builder_argdict, Builder

    parser = argparse.ArgumentParser(description="LiteX SoC on Marble V1.2")
    target_group = parser.add_argument_group(title="Target options")
    target_group.add_argument("--sys-clk-freq",   default=125e6,       help="System clock frequency.")
    target_group.add_argument("--with-spi-flash", action="store_true", help="enable SPI Flash (MMAPed)")
    ethopts = target_group.add_mutually_exclusive_group()
    ethopts.add_argument("--with-ethernet",       action="store_true", help="enable Ethernet support")
    ethopts.add_argument("--with-etherbone",      action="store_true", help="enable Etherbone support")
    target_group.add_argument("--eth-ip",         default="192.168.19.70", help="Etherbone IP address")
    target_group.add_argument("--eth-dynamic-ip", action="store_true", help="Enable dynamic Ethernet IP addresses.")
    target_group.add_argument("--build",          action="store_true", help="Build bitstream")
    target_group.add_argument("--load",           action="store_true", help="Load bitstream")
    target_group.add_argument("--with-bist",      action="store_true", help="Add DDR3 BIST Generator/Checker.")
    target_group.add_argument("--spd-dump",       type=str,            help="DDR3 conf file, dumped by the `sdram_spd`")
    builder_args(parser)
    soc_core_args(parser)
    args = parser.parse_args()

    soc = BaseSoC(
        with_ethernet = args.with_ethernet,
        with_etherbone = args.with_etherbone,
        eth_ip = args.eth_ip,
        eth_dynamic_ip = args.eth_dynamic_ip,
        with_spi_flash = args.with_spi_flash,
        **soc_core_argdict(args))
    builder = Builder(soc, **builder_argdict(args))
    vns = builder.build(run=args.build)

    if args.load:
        prog = soc.platform.create_programmer()
        print(prog.config)
        prog.load_bitstream(builder.get_bitstream_filename(mode="sram"))

if __name__ == "__main__":
    main()
