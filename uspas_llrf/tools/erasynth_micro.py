import serial
import time
import argparse


class EraSynthMicro:
    def __init__(self, port='/dev/ttyACM3', verbose=True):
        """
        ERA Synth Micro
        https://github.com/erainstruments/erasynth-micro-docs/blob/master/erasynth-micro-command-list.pdf
        """
        self.port = port
        self.ser = None
        self.verbose = verbose

    def __enter__(self):
        self.ser = serial.Serial(
            self.port, baudrate=9600, rtscts=True, timeout=1)
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self.ser and self.ser.is_open:
            self.ser.close()

    def send_command(self, command):
        if self.ser and self.ser.is_open:
            self.ser.write((command + '\r').encode('utf-8'))
            time.sleep(0.1)
        else:
            print("Device not connected.")

    def read_response(self):
        if self.ser and self.ser.is_open:
            line = self.ser.readline().decode('utf-8').strip()
            return line
        return None

    def set_frequency(self, f_hz):
        self.send_command(f'>F{int(f_hz)}')
        if self.verbose:
            print(f"Wrote Frequency [MHz]: {f_hz/1e6}")

    def read_frequency(self):
        """Read back frequency from EEPROM"""
        addr = 2239
        f = 0
        for ix, addr in enumerate(range(2239, 2244)):
            self.send_command(f'>SEA{addr}')
            self.send_command('>SER')
            r = self.read_response()
            if self.verbose:
                print(f'Addr: {addr}: Value: {r}')
            f |= int(r) << ix*8
        return f

    def set_amplitude(self, amp_dbm):
        self.send_command(f'>SA{amp_dbm}')
        if self.verbose:
            print(f"Wrote Amplitude [dBm]: {amp_dbm}")

    def read_temperature(self):
        self.send_command('>RT')
        temp = self.read_response()
        if self.verbose:
            print(f'Read  Temperature [C]: {temp}')
        return temp

    def update_lcd_home(self):
        self.send_command('>GH')


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument('--port', '-p', default='/dev/ttyACM3')
    p.add_argument('--frequency', '-f', help='frequency [Hz]', type=float)
    p.add_argument('--amplitude', '-a', help='amplitude [dBm]', type=float)
    p.add_argument('--read_freq', '-r', help='read freq [Hz]',
                   action='store_true')
    args = p.parse_args()
    with EraSynthMicro(port=args.port) as era_synth:
        era_synth.read_temperature()
        if args.read_freq:
            f = era_synth.read_frequency()
            print(f'Read Frequency [MHz]: {f/1e6}')
        if args.frequency is not None:
            era_synth.set_frequency(args.frequency)
        if args.amplitude is not None:
            era_synth.set_amplitude(args.amplitude)
        era_synth.update_lcd_home()
