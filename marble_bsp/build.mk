MODULE    = marble_bsp

VERILOG_AUTOGEN  += $(AUTOGEN_DIR)/$(MODULE)_auto.vh $(AUTOGEN_DIR)/addr_map_$(MODULE).vh
VERILOG_AUTOGEN  += $(AUTOGEN_DIR)/regmap_$(MODULE).vh
RTEFI_CLIENT_LIST = hello.v speed_test.v lb_gateway.v spi_flash.v
include $(BADGER_DIR)/rules.mk
VERILOG_AUTOGEN  += $(RTEFI_V)

$(DEPDIR)/$(MODULE)_tb.d: $(VERILOG_AUTOGEN)

$(DEPDIR)/$(MODULE).d: $(MODULE).v $(VERILOG_AUTOGEN)
	set -e; mkdir -p $(DEPDIR); \
	$(MAKEDEP) && (printf "$(MODULE)_expand.v $@: "; \
	sort -ur $@.$$$$ | tr '\n' ' '; printf "\n" ) > $@ && rm -f $@.$$$$

$(AUTOGEN_DIR)/%_expand.v: %.v $(AUTOGEN_DIR)/%_auto.vh $(AUTOGEN_DIR)/addr_map_%.vh
	$(VERILOG) $(VFLAGS_DEP) -E -o$@ $^
	sed -i '/^$$/d' $@

$(AUTOGEN_DIR)/regmap_%.vh: %.json
	mkdir -p $(AUTOGEN_DIR); \
	$(PYTHON) $(BEDROCK_DIR)/localbus/gen_regmap.py -i $< -o $@

$(AUTOGEN_DIR)/scalar_%_regmap.json: $(MODULE).v
	mkdir -p $(AUTOGEN_DIR); \
	$(PYTHON) $(BUILD_DIR)/reverse_json.py $< > $@

$(MODULE).json: $(AUTOGEN_DIR)/regmap_$(MODULE).json $(AUTOGEN_DIR)/scalar_$(MODULE)_regmap.json static_$(MODULE).json
	$(PYTHON) $(BUILD_DIR)/merge_json.py -o $@ -i $^

# this is to avoid vivado critical warnings about duplicated / redefination of module since they are already in DSP
EXCLUDE  = $(wildcard $(FPGA_FAMILY_DIR)/xilinx/*.v)
EXCLUDE += $(addprefix $(DSP_DIR)/, reg_delay.v dpram.v reg_tech_cdc.v flag_xdomain.v data_xdomain.v freq_gcount.v freq_count.v phase_diff.v phaset.v)
$(MODULE)_expand.v: $(MODULE).v $(MARBLE_BSP_REGS_H) #$(DEPDIR)/$(MODULE).d
	$(VERILOG) $(VFLAGS_DEP) -E -o $@ $(filter-out $(EXCLUDE),$(filter %.v, $^))

CLEAN += $(MODULE).json $(MODULE)_init_regs.json
CLEAN += $(MODULE)_expand.v
