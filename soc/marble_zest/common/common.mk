include $(PICORV_DIR)/rules.mk
include $(TOP)settings.mk
APP_COMMON_DIR = $(APP_SOC_DIR)/common
INC_DIR       += -I$(MARBLE_DIR)/firmware -I$(ZEST_DIR)/firmware
VIVADO_BASE    = $(dir $(shell which vivado))..

vpath %.c $(APP_COMMON_DIR)
vpath system.v $(APP_COMMON_DIR)

.PHONY: all
.DEFAULT_GOAL := all

%_tb: %_tb.v
	$(VERILOG_TB)

SRC_V  = picorv32.v system.v uart_rx.v uart_tx.v mpack.v munpack.v pico_pack.v
SRC_V += memory_pack.v # memory2_pack.v
SRC_V += stream_fifo.v shortfifo.v fifo.v uart_fifo_pack.v uart_stream.v
SRC_V += sfr_pack.v gpio_pack.v gpioz_pack.v spi_engine.v \
		 uart_pack.v wfm_pack.v xilinx7/xadc_pack.v
SRC_V += lb_bridge.v lb_merge.v lb_reading.v
SRC_V += $(DSP_DIR)/flag_xdomain.v $(DSP_DIR)/freq_count.v $(DSP_DIR)/dpram.v $(DSP_DIR)/data_xdomain.v
SRC_V += $(DSP_DIR)/phaset.v $(DSP_DIR)/phase_diff.v

SRCS   =  system.c print.c i2c_soft.c timer.c ui.c
SRCS  +=  printf.c iserdes.c
SRCS  +=  settings.h
SRCS  +=  $(MARBLE_DIR)/firmware/marble.c $(MARBLE_DIR)/firmware/marble.h
SRCS  +=  $(ZEST_DIR)/firmware/zest.c $(ZEST_DIR)/firmware/zest.h
SRCS  +=  init_zest.c
OBJS  =  $(subst .c,.o,$(filter %.c, $(SRCS))) startup.o

#size of the blockRam [bytes]
BLOCK_RAM_SIZE  = 24576
SYNTH_OPT += -DBLOCK_RAM_SIZE=$(BLOCK_RAM_SIZE)
CFLAGS += -DGIT_VERSION=\"$(GIT_VERSION)\" -I../common
CFLAGS += -DBOOTLOADER_BAUDRATE=$(BOOTLOADER_BAUDRATE)
CFLAGS += -ffunction-sections
CFLAGS += -nostartfiles
CFLAGS += -DNONSTD_PRINTF

include $(APP_SOC_DIR)/common/llrf/rules.mk
