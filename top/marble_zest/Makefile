include ../../dir_list.mk
include $(TOP)settings.mk

include $(APP_SOC_DIR)/common/common.mk
include $(BUILD_DIR)/top_rules.mk

TARGET   = marble_zest
HARDWARE = marble
# Connection to swap-git-ID feature; see comments in that file
GITID_TCL = $(BUILD_DIR)/vivado_tcl/swap_gitid.tcl

# GTX TCL configuration
GTX_CONFIG: $(BSP_DIR)/gtx_evr_config.tcl
	tclsh $(BSP_DIR)/gtx_evr_config.tcl $(FSET)

GTX_TCL = $(BSP_DIR)/gtx_evr_config.tcl

vpath %.c $(BUILD_DIR)

.PHONY: all system_config system_test evr_test clean
all: $(TARGET)_top_$(FSET).bit

IP_EXPAND = $(BSP_DIR)/marble_bsp_expand.v
IP_EXPAND += $(APP_SOC_SYN_DIR)/system_expand.v
IP_EXPAND += $(APP_DSP_DIR)/llrf_shell_expand.v

SUB_IP_DIR = $(foreach ip, $(IP_EXPAND), $(dir $(ip)))

$(BSP_DIR)/marble_bsp_expand.v:
	$(MAKE) -C $(dir $@) $(notdir $@)
$(APP_SOC_SYN_DIR)/system_expand.v:
	$(MAKE) -C $(dir $@) $(notdir $@)
$(APP_DSP_DIR)/llrf_shell_expand.v:
	$(MAKE) -C $(dir $@) $(notdir $@)

IP_JSON  = $(APP_DSP_DIR)/llrf_shell.json
IP_JSON += $(BSP_DIR)/marble_bsp.json
IP_JSON += marble_zest_top.json

$(BSP_DIR)/marble_bsp.json:
	$(MAKE) -C $(dir $@) $(notdir $@)

$(APP_DSP_DIR)/llrf_shell.json:
	$(MAKE) -C $(dir $@) $(notdir $@)

$(TARGET).json: $(IP_JSON)
	$(PYTHON) $(BUILD_DIR)/merge_json.py -o $@ -i $^

config_romx.v: $(TARGET).json
	$(PYTHON) $(BUILD_DIR)/build_rom.py -v $@ --placeholder_rev -j $< -d "$(FSET)"

# Used mostly to verify gitid reported by the LEEP Ethernet
GIT_ID = $(shell git rev-parse --verify HEAD)
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

# Construct an overall (configuration-dependent) .d file.
$(TARGET)_top.d: $(TARGET)_top.v config_romx.v $(BEDROCK_DIR)/serial_io/gmii_to_rgmii.v $(IP_EXPAND) system_top.xdc $(APP_SOC_SYN_DIR)/system32.dat
	echo $^ | tr ' ' '\n' > $@

#: Build bitstream
$(TARGET)_top_$(FSET).bit: $(TARGET)_top.tcl $(GTX_TCL) $(GITID_TCL) $(TARGET)_top.d bit_stamp_mod
	$(VIVADO_CMD) -source $< -tclargs $(TARGET)_top.d $(FSET) $(HARDWARE) "$(SYNTH_OPT)" $(GITID_TCL) $(GTX_TCL)

IP_ADDRESS = 192.168.19.$(MARBLE_SERIAL)

system_config:
	@echo "Using Marble with serial number $(MARBLE_SERIAL)"
	openocd \
	-c "adapter serial $(MARBLE_SN);" \
	-f marble.cfg \
	-c "init; xc7_program xc7.tap; pld load 0 $(TARGET)_top_$(FSET).$(GIT_32BIT_ID).bit; exit"

# check Ethernet and system selftest status
system_test:
	ping -v -c 4 -w 20 $(IP_ADDRESS)
	cd $(TOP)python && \
       test "$$($(PYTHON) test.py leep://$(IP_ADDRESS):803 gitid)" = "$(GIT_ID)" && echo "gitid OK" && \
       $(PYTHON) test.py leep://$(IP_ADDRESS):803 reg system_bist_pass | awk ' $$2!=00000001 { exit 1 }'

CLEAN += system_top.xdc top.xdc *.bin *.bit $(IP_BIT_D)
CLEAN += config_romx.v $(TARGET).json topsim.d Vmarble_zest_frame
CLEAN += $(TARGET)_top.prm bit_stamp_mod $(TARGET)_top.d *.log *.jou
CLEAN += topsim_cdc.txt topsim_yosys.json
CLEAN += $(APP_SOC_DIR)/*/*.o
CLEAN_DIRS += .Xil _xilinx obj_dir bit_stamp_mod.dSYM

include $(BUILD_DIR)/bottom_rules.mk
clean::
	$(MAKE) -C $(APP_DSP_DIR) distclean
	@for d in $(SUB_IP_DIR); do \
	    $(MAKE) -C $$d clean; \
	done;
