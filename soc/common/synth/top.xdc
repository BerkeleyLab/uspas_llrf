set_property -dict {PACKAGE_PIN F6} [get_ports GTPREFCLK_P]
set_property -dict {PACKAGE_PIN E6} [get_ports GTPREFCLK_N]

# Pmod2 J12
set_property -dict {PACKAGE_PIN C24 IOSTANDARD LVCMOS25} [get_ports {PMOD1[0]}]
set_property -dict {PACKAGE_PIN C22 IOSTANDARD LVCMOS25} [get_ports {PMOD1[1]}]
set_property -dict {PACKAGE_PIN L23 IOSTANDARD LVCMOS25} [get_ports {PMOD1[2]}]
set_property -dict {PACKAGE_PIN D21 IOSTANDARD LVCMOS25} [get_ports {PMOD1[3]}]
set_property -dict {PACKAGE_PIN K21 IOSTANDARD LVCMOS25} [get_ports {PMOD1[4]}]
set_property -dict {PACKAGE_PIN C18 IOSTANDARD LVCMOS25} [get_ports {PMOD1[5]}]
set_property -dict {PACKAGE_PIN C19 IOSTANDARD LVCMOS25} [get_ports {PMOD1[6]}]
set_property -dict {PACKAGE_PIN C17 IOSTANDARD LVCMOS25} [get_ports {PMOD1[7]}]

# Pmod2 J13
set_property -dict {PACKAGE_PIN AE7 IOSTANDARD LVCMOS15} [get_ports {PMOD2[0]}]
set_property -dict {PACKAGE_PIN V7  IOSTANDARD LVCMOS15} [get_ports {PMOD2[1]}]
set_property -dict {PACKAGE_PIN Y7  IOSTANDARD LVCMOS15} [get_ports {PMOD2[2]}]
set_property -dict {PACKAGE_PIN AF7 IOSTANDARD LVCMOS15} [get_ports {PMOD2[3]}]
set_property -dict {PACKAGE_PIN V8  IOSTANDARD LVCMOS15} [get_ports {PMOD2[4]}]
set_property -dict {PACKAGE_PIN AA8 IOSTANDARD LVCMOS15} [get_ports {PMOD2[5]}]
set_property -dict {PACKAGE_PIN Y8  IOSTANDARD LVCMOS15} [get_ports {PMOD2[6]}]
set_property -dict {PACKAGE_PIN W9  IOSTANDARD LVCMOS15} [get_ports {PMOD2[7]}]

# I2C, shared access with microcontroller
set_property -dict {PACKAGE_PIN A17 IOSTANDARD LVCMOS25} [get_ports I2C_SDA]
set_property -dict {PACKAGE_PIN B16 IOSTANDARD LVCMOS25} [get_ports I2C_SCL]
set_property -dict {PACKAGE_PIN B19 IOSTANDARD LVCMOS25} [get_ports I2C_RST]

# UART to USB
set_property -dict {PACKAGE_PIN C16 IOSTANDARD LVCMOS25} [get_ports UART_RX]
set_property -dict {PACKAGE_PIN K15 IOSTANDARD LVCMOS25} [get_ports UART_TX]
set_property -dict {PACKAGE_PIN M16 IOSTANDARD LVCMOS25} [get_ports UART_CTS]

# Bank 0 setup
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
