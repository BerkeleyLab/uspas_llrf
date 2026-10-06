# Board-level build for Marble + Zest, shared by every design.
# A design directory top/<design>/ sets DESIGN and includes this file:
#
#   DESIGN = uspas
#   include ../../dir_list.mk
#   include $(TOP_COMMON_DIR)/top_rules.mk
#
# Override hooks (set or extend them in top/<design>/Makefile before the include):
#   IP_EXPAND  += extra expanded IP sources
#   IP_JSON    += extra register maps merged into the config ROM
#   TOP_SRC    += extra top-level sources (Verilog, netlists)
#   XDC_FILES  += extra constraints, appended to system_top.xdc
#   PIN_MAP     pin map for top.xdc (default: top/common/pin_map.csv)
#   GT_TCL      GT setup TCL sourced by Vivado (default: EVR GTX)
#   SOC_DESIGN  soc/<name>/ used for firmware and SoC settings (default: DESIGN)
# Verilog hooks: design_io.vh (extra top ports) and design_mid.vh (extra IP);
# a copy in top/<design>/ takes precedence over the empty one in top/common/.

include $(TOP)settings.mk

SOC_DESIGN    ?= $(DESIGN)
SOC_BUILD_DIR  = $(SOC_DIR)/$(SOC_DESIGN)/build
# Firmware, system_expand.v and zest_fmc_dp.xdc are built per design in
# soc/<design>/build/ with the shared SoC synth Makefile
SOC_MAKE       = mkdir -p $(SOC_BUILD_DIR) && $(MAKE) -C $(SOC_BUILD_DIR) -f $(abspath $(SOC_COMMON_DIR)/synth/Makefile) DESIGN=$(SOC_DESIGN)

include $(SOC_COMMON_DIR)/common.mk
include $(BUILD_DIR)/top_rules.mk

TARGET   = marble_zest
# Connection to swap-git-ID feature; see comments in that file
GITID_TCL = $(BUILD_DIR)/vivado_tcl/swap_gitid.tcl

GT_TCL  ?= $(BEDROCK_DIR)/serial_io/EVG_EVR/gt_tcl/evr_gtx.tcl
PIN_MAP ?= $(TOP_COMMON_DIR)/pin_map.csv
vpath %.c $(BUILD_DIR)

.PHONY: all system_config system_test evr_test clean
all: $(TARGET)_top_$(DESIGN).bit

IP_EXPAND := $(BSP_DIR)/marble_bsp_expand.v $(SOC_BUILD_DIR)/system_expand.v $(DESIGNS_DIR)/$(DESIGN)/llrf_shell_expand.v $(IP_EXPAND)

SUB_IP_DIR = $(BSP_DIR)/ $(DESIGNS_DIR)/$(DESIGN)/

$(BSP_DIR)/marble_bsp_expand.v:
	$(MAKE) -C $(dir $@) $(notdir $@)
$(SOC_BUILD_DIR)/system_expand.v:
	$(SOC_MAKE) $(notdir $@)
$(DESIGNS_DIR)/$(DESIGN)/llrf_shell_expand.v:
	$(MAKE) -C $(dir $@) $(notdir $@)

IP_JSON := $(DESIGNS_DIR)/$(DESIGN)/llrf_shell.json $(BSP_DIR)/marble_bsp.json $(TOP_COMMON_DIR)/marble_zest_top.json $(IP_JSON)

$(BSP_DIR)/marble_bsp.json:
	$(MAKE) -C $(dir $@) $(notdir $@)

$(DESIGNS_DIR)/$(DESIGN)/llrf_shell.json:
	$(MAKE) -C $(dir $@) $(notdir $@)

$(TARGET).json: $(IP_JSON)
	$(PYTHON) $(BUILD_DIR)/merge_json.py -o $@ -i $^

config_romx.v: $(TARGET).json
	$(PYTHON) -m leep.build_rom -v $@ --placeholder_rev -j $< -d "$(DESIGN)"

# Used mostly to verify gitid reported by the LEEP Ethernet
GIT_ID = $(shell git rev-parse --verify HEAD)
GIT_32BIT_ID = $(shell git rev-parse --short=8 --verify HEAD)
SYNTH_OPT += -DGIT_32BIT_ID=32'h$(GIT_32BIT_ID)

$(SOC_BUILD_DIR)/system32.dat:
	$(SOC_MAKE) system32.dat

$(SOC_BUILD_DIR)/zest_fmc_dp.xdc:
	$(SOC_MAKE) zest_fmc_dp.xdc

top.xdc: $(BOARD_SUPPORT_DIR)/marble/Marble.xdc $(PIN_MAP)
	$(PYTHON) $(BADGER_DIR)/tests/meta-xdc.py $^ > $@

system_top.xdc: $(TOP_COMMON_DIR)/timing.xdc $(SOC_BUILD_DIR)/zest_fmc_dp.xdc top.xdc $(XDC_FILES)
	cat $^ > $@

# Construct an overall (configuration-dependent) .d file.
$(TARGET)_top.d: $(TOP_COMMON_DIR)/$(TARGET)_top.v config_romx.v $(BEDROCK_DIR)/serial_io/gmii_to_rgmii.v $(IP_EXPAND) $(TOP_SRC) system_top.xdc $(SOC_BUILD_DIR)/system32.dat
	echo $^ | tr ' ' '\n' > $@

#: Build bitstream
$(TARGET)_top_$(DESIGN).bit: $(TOP_COMMON_DIR)/$(TARGET)_top.tcl $(GT_TCL) $(GITID_TCL) $(TARGET)_top.d bit_stamp_mod
	$(VIVADO_CMD) -source $< -tclargs $(TARGET)_top.d $(DESIGN) "$(SYNTH_OPT)" $(GITID_TCL) $(GT_TCL)

IP_ADDRESS = 192.168.19.$(MARBLE_SERIAL)

BITSTREAM = $(TARGET)_top_$(DESIGN).$(GIT_32BIT_ID).bit
system_config:
	@echo "Using Marble with serial number $(MARBLE_SERIAL)"
	openocd \
	-c "adapter serial $(MARBLE_SN);" \
	-f $(TOP_COMMON_DIR)/marble.cfg \
	-c "init; xc7_program xc7.tap; pld load 0 $(BITSTREAM); exit"

# check Ethernet and system selftest status
system_test:
	ping -v -c 4 -w 20 $(IP_ADDRESS)
	test "$$(leep leep://$(IP_ADDRESS):803 gitid)" = "$(GIT_ID)" && echo "gitid OK" && \
	leep leep://$(IP_ADDRESS):803 reg system_bist_pass | awk ' $$2!=00000001 { exit 1 }'

#: Verilator simulation of the full top (see topsim.sh)
topsim:
	sh $(TOP_COMMON_DIR)/topsim.sh

CLEAN += system_top.xdc top.xdc *.bin *.bit $(IP_BIT_D)
CLEAN += config_romx.v $(TARGET).json topsim.d Vmarble_zest_frame system32.dat
CLEAN += $(TARGET)_top.prm bit_stamp_mod $(TARGET)_top.d *.log *.jou
CLEAN += topsim_cdc.txt topsim_yosys.json
CLEAN_DIRS += .Xil _xilinx obj_dir bit_stamp_mod.dSYM $(SOC_BUILD_DIR)

include $(BUILD_DIR)/bottom_rules.mk
clean::
	@for d in $(SUB_IP_DIR); do \
	    $(MAKE) -C $$d clean; \
	done;
