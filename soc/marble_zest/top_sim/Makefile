include ../../../dir_list.mk
include $(BUILD_DIR)/top_rules.mk
include $(APP_SOC_DIR)/common/common.mk

TARGET = system
BOOTLOADER_BAUDRATE = 10416666

SRC_V  += $(APP_SOC_DIR)/synth/system_top.v xilinx7_clocks.v
SRC_V  += $(ZEST_DIR)/zest_spi_dio_pack.v $(ZEST_DIR)/zest.v $(ZEST_DIR)/zest_clk_map.v
SRC_V  += $(BOARD_SUPPORT_DIR)/fmc11x/dco_buf.v \
		  $(BOARD_SUPPORT_DIR)/fmc11x/iserdes_pack.v \
		  $(BOARD_SUPPORT_DIR)/fmc11x/idelay_wrap.v

SRC_V  += $(VIVADO_BASE)/data/verilog/src/glbl.v
OBJS   += 0x000.lds
CFLAGS += -DSIMULATION -DXSIM_DBG

all: $(TARGET)_top.vcd
$(TARGET).elf: $(OBJS)

# simulation
system_top_tb: system_top_tb.v $(SRC_V) $(TARGET)32.dat
	xvlog -nolog -d SIMULATE -d BLOCK_RAM_SIZE=$(BLOCK_RAM_SIZE) $(filter %.v,$^)
	xelab -nolog -L unisims_ver -L secureip $@ glbl -s $@ -timescale 1ns/1ps

system_top.vcd: system_top_tb system32.dat
	xsim -nolog -R $< -testplusarg vcd

CLEAN += $(TARGET)_top.xdc
CLEAN += xelab.pb xsim*.jou xsim*.log webtalk*.jou webtalk*.log vivado*.log xvlog.pb
CLEAN_DIRS += xsim.dir .Xil _xilinx
include $(BUILD_DIR)/bottom_rules.mk
