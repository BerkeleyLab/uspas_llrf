import numpy as np


class MarbleDevInfo:
    """ BSP info data structure, defined by marble.h and zest.h """
    ina219_struct = [
        ('i2c_mux_sel', 'u1'),
        ('i2c_addr', 'u1'),
        ('refdes', 'S4'),
        ('name', 'S4'),
        ('rshunt_mOhm', 'u2'),
        ('current_lsb_uA', 'u2'),
        ('vshunt', 'i2'),    # uV
        ('vbus', 'u2'),      # mV
        ('power', 'u2'),     # uW
        ('current', 'i4'),   # uA
    ]

    pca9555_struct = [
        ('i2c_mux_sel', 'u1'),
        ('i2c_addr', 'u1'),
        ('refdes', 'S4'),
        ('name', 'S4'),
        ('i0_val', 'u1'),
        ('i1_val', 'u1'),
    ]

    qsfp_struct = [
        ('module_present', '?'),
        ('i2c_mux_sel', 'u1'),
        ('i2c_addr', 'u1'),
        ('page_select', 'u1'),
        ('chan_stat_los', 'u1'),
        ('temperature', '>i2'),
        ('XXX', 'V1'),  # XXX 8-7 = 1
        ('voltage', 'u2'),          # mV
        ('bias_current', 'u2', 4),  # uA
        ('rx_power', 'u2', 4),      # uW
        ('tx_power', 'u2', 4),      # uW
        ('vendor_name', 'S16'),
        ('part_num', 'S16'),
        ('serial_num', 'S16'),
    ]

    adn4600_struct = [
        ('i2c_mux_sel', 'u1'),
        ('i2c_addr', 'u1'),
        ('refdes', 'S6'),
        ('xpt_status', 'u1', 8),
    ]

    si570_struct = [
        ('i2c_mux_sel', 'u1'),
        ('i2c_addr', 'u1'),
        ('regs', 'V6'),
        ('f_xtal_hz', 'u8'),
        ('rfreq', 'u8'),
        ('f_reset_hz', 'u8'),
        ('f_dco_hz', 'u8'),
        ('f_out_hz', 'u8'),
        ('start_addr', 'u1'),
        ('hs_div', 'u1'),
        ('n1', 'u1'),
        ('S', 'V5'),  # XXX 8-3 = 5
    ]

    marble_info_dtype = [
        ('marble_variant', 'u4'),
        ('ina219', ina219_struct, 3),    # 12V, fmc1, fmc2
        ('pca9555', pca9555_struct, 2),  # QSFP, MISC
        ('qsfp', qsfp_struct, 2),        # QSFP1, QSFP2
        ('adn4600', adn4600_struct),
        ('si570', si570_struct)
    ]

    marble_var = {
        0: 'V1.2',
        1: 'V1.3',
        2: 'V1.4',
        3: 'Unknown',
    }

    zest_fcnt_names = {
        0: 'ADC0_DIV',
        1: 'ADC1_DIV',
        2: 'DAC_DCO',
        3: 'DSP_CLK',
    }

    zest_phdiff_names = {
        0: 'ADC0_DIV',
        1: 'ADC1_DIV',
        2: 'DAC_DCO',
    }

    zest_status_dtype = [
        ('zest_frequencies', 'u4', 4),
        ('zest_phases', 'i2', 3),
        ('amc7823_adcs', 'u2', 9),
        ('ad7794_adcs', 'u4', 6),
    ]

    info_dtype = [
        ('marble_info', marble_info_dtype),
        ('zest_status', zest_status_dtype),
    ]

    data = None

    def __init__(self):
        self.length = np.dtype(self.info_dtype).itemsize

    def decode_data(self, buf):
        """convert raw register read back into structured array"""
        buf = buf[:self.length].astype(np.uint8).tobytes()
        self.data = np.frombuffer(buf, dtype=self.info_dtype)
        return self.data

    def format_marble_info(self, d):
        """format marble_info from decoded data
        Args:
          d: structured array from decode_data()
        Returns:
          string: formatted string for display
        """
        s = f"Marble Variant: {self.marble_var[d['marble_variant']]}\n"
        item = d['adn4600']
        s += f"ADN4600 {item['refdes'].decode()}:\n"
        for ix in range(4):
            s += f"  IN {item['xpt_status'][ix]} -> OUT {ix}\n"
        for ix in range(3):
            item = d['ina219'][ix]
            s += (
                f"INA219 {item['refdes'].decode()}, {item['name'].decode()}:\n"
                f"  Vshunt     : {item['vshunt'] / 1e3:8.1f} mV\n"
                f"  Power      : {item['power'] / 1e3:8.1f} mW\n"
                f"  Vbus       : {item['vbus'] / 1e3:8.1f} V\n"
                f"  Current    : {item['current'] / 1e3:8.1f} mA\n"
            )
        for ix in range(2):
            item = d['pca9555'][ix]
            s += (
                f" PCA9555 {item['refdes'].decode()}, "
                f"{item['name'].decode()}:\n"
                f"  I0         :    {item['i0_val']:08b}\n"
                f"  I1         :    {item['i1_val']:08b}\n"
            )
        for ix in range(2):
            item = d['qsfp'][ix]
            if item['module_present']:
                s += (
                    f"QSFP {ix + 1} is present:\n"
                    f"  Vendor     :    {item['vendor_name'].decode():16s}\n"
                    f"  Part       :    {item['part_num'].decode():16s}\n"
                    f"  Serial     :    {item['serial_num'].decode():16s}\n"
                    f"  TXRX_LOS   :    {item['chan_stat_los']:8b}\n"
                    f"  Temp       :    {item['temperature']} C\n"
                    f"  Volt       :    {item['voltage']} mV\n"
                )
                for ch in range(4):
                    s += (
                        f"  TxBias{ch}    :    {item['bias_current'][ch]} uA\n"
                        f"  TxPwr{ch}     :    {item['tx_power'][ch]} uW\n"
                        f"  RxPwr{ch}     :    {item['rx_power'][ch]} uW\n"
                    )
        s += 'SI570:\n'
        item = d['si570']
        s += (
            f"  regs       :    {item['regs']}\n"
            f"  HSDIV      :    {item['hs_div']}\n"
            f"  N1         :    {item['n1']}\n"
            f"  f_reset    :    {item['f_reset_hz'] / 1e6:8.3f} MHz\n"
            f"  f_xtal_hz  :    {item['f_xtal_hz'] / 1e6:8.3f} MHz\n"
            f"  f_out_hz   :    {item['f_out_hz'] / 1e6:8.3f} MHz\n"
        )
        return s

    def format_zest_status(self, d):
        """format zest_status from decoded data
        Args:
          d: structured array from decode_data()
        Returns:
          string: formatted string for display
        """
        s = 'Zest Clocks:\n'
        item = d['zest_frequencies']
        for ix in range(4):
            s += (
                f"  Freq  {self.zest_fcnt_names[ix]:8s} : "
                f"{item[ix] * 125 / (1 << 16):8.3f} MHz\n"
            )
        item = d['zest_phases']
        for ix in range(3):
            s += (
                f"  Phase {self.zest_phdiff_names[ix]:8s} : "
                f"{item[ix] / (1 << 16):8.3f} UI\n"
            )
        s += 'Zest AMC7823:\n'
        item = d['amc7823_adcs']
        for ix in range(9):
            val = np.bitwise_and(item[ix], 0xfff)
            if ix == 8:
                s += (
                    f"  Temperature    : "
                    f"{(val * 2.6 * 0.61 - 273):8.3f} C\n"
                )
            else:
                s += (
                    f"  Voltage {[ix]}    : "
                    f"{val * 2.5 / 0xfff:8.3f} V\n"
                )
        s += 'Zest AD7794:\n'
        item = d['ad7794_adcs']
        for ix in range(6):
            s += (
                f"  Voltage {[ix]}    : "
                f"{(item[ix] * 1.17 / 0xffffff):8.3f} V\n"
            )
        return s

    def __repr__(self):
        assert self.data is not None
        s = self.format_marble_info(self.data[0]['marble_info'])
        s += self.format_zest_status(self.data[0]['zest_status'])
        return s
