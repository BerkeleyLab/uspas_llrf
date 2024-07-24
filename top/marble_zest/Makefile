XILINX_TOOL = VIVADO
include ../../dir_list.mk

include $(TOP)settings.mk
include $(BUILD_DIR)/top_rules.mk
include $(APP_SOC_DIR)/common/common.mk

TARGET = marble_zest

.PHONY: all system_config system_test clean
all: $(TARGET)_top.bit

IP_EXPAND = $(UDP_RGMII_DIR)/udp_rgmii_expand.v
IP_EXPAND += $(APP_SOC_SYN_DIR)/system_expand.v
IP_EXPAND += $(APP_DSP_DIR)/llrf_shell_expand.v

SUB_IP_DIR = $(foreach ip, $(IP_EXPAND), $(dir $(ip)))

$(UDP_RGMII_DIR)/udp_rgmii_expand.v:
	$(MAKE) -C $(dir $@) $(notdir $@)
$(APP_SOC_SYN_DIR)/system_expand.v:
	$(MAKE) -C $(dir $@) $(notdir $@)
$(APP_DSP_DIR)/llrf_shell_expand.v:
	$(MAKE) -C $(dir $@) $(notdir $@)

GIT_32BIT_ID = $(shell git rev-parse --short=8 --verify HEAD)
SYNTH_OPT += -DGIT_32BIT_ID=32'h$(GIT_32BIT_ID)

$(APP_SOC_SYN_DIR)/system32.dat:
	$(MAKE) -C $(APP_SOC_SYN_DIR) system32.dat

$(APP_SOC_SYN_DIR)/zest_fmc_dp.xdc:
	$(MAKE) -C $(APP_SOC_SYN_DIR) zest_fmc_dp.xdc

top.xdc: $(BOARD_SUPPORT_DIR)/$(HARDWARE)/Marble.xdc pin_map.csv
	$(PYTHON) $(BADGER_DIR)/tests/meta-xdc.py $^ > $@

system_top.xdc: timing.xdc $(APP_SOC_SYN_DIR)/zest_fmc_dp.xdc top.xdc
	cat $^ > $@

#: Build bitstream
$(TARGET)_top.bit: system_top.xdc $(TARGET)_top.v $(IP_EXPAND) $(APP_SOC_SYN_DIR)/system32.dat $(GTP_DEPS)

IP_ADDRESS = 192.168.19.$(MARBLE_SERIAL)

system_config:
	@echo "Using Marble with serial number $(MARBLE_SERIAL)"
	openocd \
	-c "adapter serial 0000$(MARBLE_SERIAL);" \
	-f marble.cfg \
	-c "init; xc7_program xc7.tap; pld load 0 $(TARGET)_top.bit; exit"

# check Ethernet and system selftest status
system_test:
	ping -v -c 4 -w 20 $(IP_ADDRESS)
	cd $(TOP)python && \
	$(PYTHON) test.py leep://$(IP_ADDRESS):803 reg system_bist_pass | awk ' $$2!=00000001 { exit 1 }'

CLEAN += system_top.xdc $(TARGET)_top.bin $(TARGET)_top.bit $(IP_BIT_D)
CLEAN += $(TARGET)_top.prm
CLEAN_DIRS += .Xil _xilinx

include $(BUILD_DIR)/bottom_rules.mk
clean::
	@for d in $(SUB_IP_DIR); do \
	    $(MAKE) -C $$d clean; \
	done;

#ifeq (,$(MAKECMDGOALS))
#    -include $(DEPDIR)/$(TARGET)_top.bit.d
#endif
