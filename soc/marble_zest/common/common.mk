include $(PICORV_DIR)/rules.mk
include $(TOP)settings.mk
APP_COMMON_DIR = $(APP_SOC_DIR)/common
INC_DIR       += -I$(BOARD_SUPPORT_DIR)/marble_soc/firmware -I$(BOARD_SUPPORT_DIR)/zest_soc/firmware
VIVADO_BASE    = $(dir $(shell which vivado))..

vpath %.c $(APP_COMMON_DIR)
vpath system.v $(APP_COMMON_DIR)
vpath %.c $(MB_MOCKUP_DIR)/lib

.PHONY: all
.DEFAULT_GOAL := all

%_tb: %_tb.v
	$(VERILOG_TB)

SRC_V  = picorv32.v system.v uart_rx.v uart_tx.v mpack.v munpack.v pico_pack.v
SRC_V += memory_pack.v # memory2_pack.v
SRC_V += stream_fifo.v shortfifo.v fifo.v uart_fifo_pack.v uart_stream.v
SRC_V += sfr_pack.v gpio_pack.v gpioz_pack.v spi_engine.v \
		 uart_pack.v wfm_pack.v awg_pack.v xilinx7/xadc_pack.v
SRC_V += lb_bridge.v lb_merge.v lb_reading.v
SRC_V += $(DSP_DIR)/flag_xdomain.v $(DSP_DIR)/freq_gcount.v $(DSP_DIR)/freq_count.v $(DSP_DIR)/dpram.v
SRC_V += $(DSP_DIR)/data_xdomain.v $(DSP_DIR)/reg_tech_cdc.v
SRC_V += $(DSP_DIR)/phaset.v $(DSP_DIR)/phase_diff.v
SRC_V += $(MB_MOCKUP_DIR)/common/rs485_uart.v fifo.v spi_pack.v

SRCS   =  system.c print.c i2c_soft.c timer.c console.c evr_gt_wrapper.c
SRCS  +=  init_modbus.c mb_client.c mb_array_map.c
SRCS  +=  printf.c iserdes.c
SRCS  +=  settings.h
SRCS  +=  $(BOARD_SUPPORT_DIR)/marble_soc/firmware/marble.c
SRCS  +=  $(BOARD_SUPPORT_DIR)/zest_soc/firmware/zest.c
SRCS  +=  init_zest_$(FSET).c
SRCS  +=  init_marble_$(FSET).c

# The source of truth
MB_REGS_TOML=$(APP_COMMON_DIR)/mb_addr_map.toml
# The generated files
MB_REGS_H=modbus_registers.h
MB_REGS_C=modbus_bus_handlers.c
MB_REGS_INCLUDES=localbus.h settings.h llrf_regs_addr.h init_modbus.h
$(MB_REGS_H) $(MB_REGS_C): $(MB_REGS_TOML)
	$(PYTHON) $(APP_COMMON_DIR)/modbusAddrMap.py $< --header $(MB_REGS_H) --source $(MB_REGS_C) $(addprefix -I, $(MB_REGS_INCLUDES))

init_modbus.o: $(MB_REGS_H) $(MB_REGS_C)
SRCS +=  $(MB_REGS_C)
OBJS  =  $(subst .c,.o,$(filter %.c, $(SRCS))) startup_irq.o

#size of the blockRam [bytes]
#BLOCK_RAM_SIZE  = 32768
BLOCK_RAM_SIZE  = 65536
SYNTH_OPT += -DBLOCK_RAM_SIZE=$(BLOCK_RAM_SIZE)
CFLAGS += -DGIT_VERSION=\"$(GIT_VERSION)\" -I../common
CFLAGS += -DBOOTLOADER_BAUDRATE=$(BOOTLOADER_BAUDRATE)
CFLAGS += -ffunction-sections
CFLAGS += -nostartfiles
CFLAGS += -DNONSTD_PRINTF
CFLAGS += -DUSPAS_LLRF_FSET=\"$(FSET)\"

CLEAN += init_zest_$(FSET).o init_marble_$(FSET).o
CLEAN += $(MB_REGS_H) $(MB_REGS_C)
CFLAGS += -I$(MB_MOCKUP_DIR)/lib

include $(APP_SOC_DIR)/common/llrf/rules.mk
