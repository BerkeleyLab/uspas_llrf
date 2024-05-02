XILINX_TOOL = VIVADO
include ../../dir_list.mk

include $(BUILD_DIR)/top_rules.mk
include $(APP_SOC_DIR)/common/common.mk

TARGET = marble_zest

.PHONY: all system_config clean
all: $(TARGET)_top.bit

IP_EXPAND = $(UDP_RGMII_DIR)/udp_rgmii_expand.v
IP_EXPAND += $(APP_SOC_SYN_DIR)/system_expand.v
IP_EXPAND += $(APP_DSP_DIR)/llrf_shell_expand.v
# All of the below are needed for the mmc mailbox
IP_EXPAND += $(PROJECTS_DIR)/test_marble_family/mmc_mailbox.v
IP_EXPAND += $(HOMELESS_DIR)/fake_dpram.v
IP_EXPAND += $(BADGER_DIR)/tests/spi_gate.v
IP_EXPAND += $(DSP_DIR)/dpram.v

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

#: Program bitstream and ping with the default firmware IP address
SERIAL = ""

# If IP_ADDRESS is defined, this will do nothing (hopefully)
# If SERIAL is set, IP_ADDRESS will be configured for that serial number
# Otherwise, we fall back to the default 192.168.19.122
ifeq ($(strip $(SERIAL)),)
IP_ADDRESS?=192.168.19.122
else
IP_ADDRESS?=192.168.19.$(SERIAL)
endif

system_config:
	@echo "Using Marble with serial number ${SERIAL}"
	openocd -c "adapter driver ftdi; ftdi_serial 0000${SERIAL};" -f marble.cfg -c "transport select jtag; init; xc7_program xc7.tap; pld load 0  $(TARGET)_top.bit; exit"
	sleep 5 && ping -v -c 4 -w 20 $(IP_ADDRESS)

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
