# SoC firmware settings for the alsu design, included by soc/common/common.mk.
# Modbus-RTU client on UART1: rs485_uart sits on the SoC expansion port
# (instantiated in top/alsu/design_mid.vh). 64K program memory (D22).
BLOCK_RAM_SIZE = 65536

# rs485_uart is expanded with the SoC sources
SRC_V += $(MB_MOCKUP_DIR)/common/rs485_uart.v spi_pack.v

SRCS   += alsu_hooks.c init_modbus.c mb_client.c mb_array_map.c
vpath %.c $(MB_MOCKUP_DIR)/lib
CFLAGS += -I$(MB_MOCKUP_DIR)/lib

# Modbus register map, generated from mb_addr_map.toml (the source of truth)
MB_REGS_TOML     = $(SOC_DESIGN_DIR)/mb_addr_map.toml
MB_REGS_H        = modbus_registers.h
MB_REGS_C        = modbus_bus_handlers.c
MB_REGS_INCLUDES = localbus.h settings.h llrf_regs_addr.h init_modbus.h
$(MB_REGS_H) $(MB_REGS_C): $(MB_REGS_TOML)
	$(PYTHON) $(SOC_DESIGN_DIR)/modbusAddrMap.py $< --header $(MB_REGS_H) --source $(MB_REGS_C) $(addprefix -I, $(MB_REGS_INCLUDES))

init_modbus.o: $(MB_REGS_H) $(MB_REGS_C)
SRCS  += $(MB_REGS_C)
CLEAN += $(MB_REGS_H) $(MB_REGS_C)
