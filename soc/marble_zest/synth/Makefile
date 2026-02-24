include ../../../dir_list.mk
XILINX_TOOL         = VIVADO
include $(TOP)settings.mk
include $(BUILD_DIR)/top_rules.mk
include $(APP_SOC_DIR)/common/common.mk

TARGET              = system
BOOTLOADER_SERIAL   = $(shell readlink -f /dev/serial/by-id/usb-LBNL_Marble_$(MARBLE_SN)-if02-port0)
BOOTLOADER_BAUDRATE = 115200

SRC_V  += xilinx7_clocks.v
SRC_V  += $(ZEST_DIR)/zest_spi_dio_pack.v $(ZEST_DIR)/zest_clk_map.v
SRC_V  += $(ZEST_DIR)/zest.v
SRC_V  += $(ZEST_DIR)/zest_dac_interp.v
SRC_V  += $(BOARD_SUPPORT_DIR)/fmc11x/dco_buf.v \
		  $(BOARD_SUPPORT_DIR)/fmc11x/iserdes_pack.v \
		  $(BOARD_SUPPORT_DIR)/fmc11x/idelay_wrap.v
OBJS   += bootloader.o 0x0e0.lds

all: $(TARGET)_top.bit

$(TARGET).elf: $(OBJS)
$(TARGET)_top.bit: system_top.xdc system_top.v $(SRC_V) $(TARGET)32.dat

zest_pinmap.txt: $(BOARD_SUPPORT_DIR)/zest/digitizer_digital_pin.txt
	$(PYTHON) $(ZEST_DIR)/remap.py -p $(BEDROCK_DIR) --vita57 $(ZEST_DIR)/vita_57.1_pinout.txt -o $@

zest_fmc_dp.xdc: zest_pinmap.txt
	$(PYTHON) $(ZEST_DIR)/meta-xdc_vita57.py -i $< -c $(BOARD_SUPPORT_DIR)/$(HARDWARE)/Marble.xdc -o $@

system_top.xdc: top.xdc timing.xdc zest_fmc_dp.xdc
	cat $^ > $@

system_config: $(TARGET)_top.bit
	openocd -f $(BOARD_SUPPORT_DIR)/marblemini/marble.cfg -c "transport select jtag; init; xc7_program xc7.tap; pld load 0 $<; exit"

# this is to avoid vivado critical warnings about duplicated / redefination of module since they are already in DSP
EXCLUDE = $(addprefix $(DSP_DIR)/, dpram.v flag_xdomain.v data_xdomain.v reg_delay.v reg_tech_cdc.v freq_gcount.v freq_count.v)
system_expand.v: $(SRC_V)
	$(VERILOG) $(SYNTH_OPT) -E -o$@ $(filter-out $(EXCLUDE),$(filter %.v, $^))

CLEAN += $(TARGET)_top.bin $(TARGET)_top.bit $(TARGET)_top.xdc
CLEAN += zest_pinmap.txt zest_fmc_dp.xdc
CLEAN += system_expand.v
CLEAN += xvlog.pb xvlog.log
CLEAN += init_*.o
CLEAN_DIRS += .Xil _xilinx xsim.dir
include $(BUILD_DIR)/bottom_rules.mk
