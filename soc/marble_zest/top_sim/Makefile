include ../../../dir_list.mk
include $(BUILD_DIR)/top_rules.mk
include $(APP_SOC_DIR)/common/common.mk

TARGET = system
BOOTLOADER_BAUDRATE = 10416666

SRC_V  += $(APP_SOC_DIR)/synth/system_top.v xilinx7_clocks.v
SRC_V  += $(ZEST_DIR)/zest_spi_dio_pack.v $(ZEST_DIR)/zest_clk_map.v
SRC_V  += $(ZEST_DIR)/zest.v
SRC_V  += $(ZEST_DIR)/zest_dac_interp.v
SRC_V  += $(BOARD_SUPPORT_DIR)/fmc11x/dco_buf.v \
		  $(BOARD_SUPPORT_DIR)/fmc11x/iserdes_pack.v \
		  $(BOARD_SUPPORT_DIR)/fmc11x/idelay_wrap.v

SRC_V  += $(VIVADO_BASE)/data/verilog/src/glbl.v
OBJS   += 0x000.lds
CFLAGS += -DSIMULATION -DXSIM_DBG -DFCNT_WIDTH=10

all: $(TARGET)_top.vcd
$(TARGET).elf: $(OBJS)

XVLOG_ARGS = -d SIMULATE -d BLOCK_RAM_SIZE=$(BLOCK_RAM_SIZE)
XVLOG_ARGS += -d DSP_FREQ_MHZ=$(CFG_$(FSET)_DSP_FREQ_MHZ)
XVLOG_ARGS += -d DAC_INTERP_COEFF_R=$(CFG_$(FSET)_DAC_INTERP_COEFF_R)
# simulation
system_top_tb: system_top_tb.v $(SRC_V) $(TARGET)32.dat
	xvlog -nolog $(XVLOG_ARGS) $(filter %.v,$^)
	xelab -nolog -L unisims_ver -L secureip $@ glbl -s $@ -timescale 1ns/1ps

system_top.vcd: system_top_tb system32.dat
	xsim -nolog -R $< -testplusarg vcd

CLEAN += $(TARGET)_top.xdc $(TARGET)_top_tb.wdb
CLEAN += xelab.pb xsim*.jou xsim*.log webtalk*.jou webtalk*.log vivado*.log xvlog.pb
CLEAN_DIRS += xsim.dir .Xil _xilinx
include $(BUILD_DIR)/bottom_rules.mk
