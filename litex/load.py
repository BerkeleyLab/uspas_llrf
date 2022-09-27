from litex_boards.platforms import berkeleylab_marble
import argparse

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Config FPGA via JTAG')
    parser.add_argument("--bit_file",
        default='build/berkeleylab_marble/gateware/berkeleylab_marble.bit',
        help='bitstream file')
    args = parser.parse_args()

    prog = berkeleylab_marble.Platform().create_programmer()
    prog.load_bitstream(args.bit_file)
