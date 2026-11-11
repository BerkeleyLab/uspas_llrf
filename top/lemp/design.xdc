# LEMP pin settings, appended to system_top.xdc (after top.xdc, so these win)
# PMOD1: rear I/O board, pulled up; the others pulled down
set_property -dict {DRIVE 4 SLEW FAST PULLTYPE PULLUP} [get_ports {PMOD1*}]
set_property -dict {DRIVE 4 SLEW FAST PULLTYPE PULLDOWN} [get_ports {PMOD2*}]
set_property -dict {DRIVE 4 SLEW FAST PULLTYPE PULLDOWN} [get_ports {ZEST_PMOD1*}]
set_property -dict {DRIVE 4 SLEW FAST PULLTYPE PULLDOWN} [get_ports {ZEST_PMOD2*}]
