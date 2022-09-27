set_property -dict {PACKAGE_PIN F6} [get_ports GTPREFCLK_P]
set_property -dict {PACKAGE_PIN E6} [get_ports GTPREFCLK_N]

set_property -dict {PACKAGE_PIN C18 IOSTANDARD LVCMOS33} [get_ports {LED[0]}]
set_property -dict {PACKAGE_PIN D22 IOSTANDARD LVCMOS33} [get_ports {LED[1]}]
set_property -dict {PACKAGE_PIN E22 IOSTANDARD LVCMOS33} [get_ports {LED[2]}]
set_property -dict {PACKAGE_PIN G21 IOSTANDARD LVCMOS33} [get_ports {LED[3]}]
set_property -dict {PACKAGE_PIN D21 IOSTANDARD LVCMOS33} [get_ports {LED[4]}]
set_property -dict {PACKAGE_PIN E21 IOSTANDARD LVCMOS33} [get_ports {LED[5]}]
set_property -dict {PACKAGE_PIN F21 IOSTANDARD LVCMOS33} [get_ports {LED[6]}]
set_property -dict {PACKAGE_PIN G22 IOSTANDARD LVCMOS33} [get_ports {LED[7]}]

# I2C, shared access with microcontroller
set_property -dict {PACKAGE_PIN A13 IOSTANDARD LVCMOS33} [get_ports TWI_SDA]
set_property -dict {PACKAGE_PIN A14 IOSTANDARD LVCMOS33} [get_ports TWI_SCL]
set_property -dict {PACKAGE_PIN C22 IOSTANDARD LVCMOS33} [get_ports TWI_RST]

# UART to USB
set_property -dict {PACKAGE_PIN U7 IOSTANDARD LVCMOS25} [get_ports UART_RX]
set_property -dict {PACKAGE_PIN Y9 IOSTANDARD LVCMOS25} [get_ports UART_TX]
set_property -dict {PACKAGE_PIN W9 IOSTANDARD LVCMOS25} [get_ports UART_CTS]

# Bank 0 setup
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
