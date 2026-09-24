include ../../dir_list.mk
include $(TOP)settings.mk
include $(BUILD_DIR)/top_rules.mk
include $(BUILD_DIR)/newad_top_rules.mk
include $(CORDIC_DIR)/rules.mk

MODULE = llrf_shell
LB_AW = 17
NEWAD_ARGS += -m
NEWAD_ARGS_llrf_shell = -b69632
NEWAD_DIRS = .,$(APP_DSP_DIR),$(DSP_DIR)

LLRF_SHELL_SRC ?= $(if $(wildcard llrf_shell.v),llrf_shell.v,$(APP_DSP_DIR)/llrf_shell.v)

vpath %.v $(APP_DSP_DIR) $(DSP_DIR) $(CORDIC_DIR) $(AUTOGEN_DIR)
VFLAGS_DEP += -I. -I$(APP_DSP_DIR) -y$(APP_DSP_DIR) -y$(DSP_DIR) -y$(CORDIC_DIR) -y$(SERIAL_IO_DIR)/EVG_EVR
VFLAGS_DEP += -I$(AUTOGEN_DIR) -y$(AUTOGEN_DIR) -I$(BEDROCK_DIR)/localbus -y$(BEDROCK_DIR)/localbus
VFLAGS += $(VFLAGS_DEP) -g2012

.PHONY: all clean
all: $(MODULE)_expand.v $(MODULE).json

cordicg_b22.v: $(CORDIC_DIR)/cordicgx.py
	$(PYTHON) $< 22 $@

$(AUTOGEN_DIR)/addr_map_$(MODULE).vh $(AUTOGEN_DIR)/$(MODULE)_auto.vh $(AUTOGEN_DIR)/regmap_$(MODULE).json: $(LLRF_SHELL_SRC)
	mkdir -p $(AUTOGEN_DIR)
	$(PYTHON) $(BUILD_DIR)/newad.py -a $(AUTOGEN_DIR)/addr_map_$(MODULE).vh -o $(AUTOGEN_DIR)/$(MODULE)_auto.vh -l -r $(AUTOGEN_DIR)/regmap_$(MODULE).json -i $< -w $(LB_AW) $(NEWAD_ARGS) $(NEWAD_ARGS_$(MODULE))

$(AUTOGEN_DIR)/scalar_$(MODULE)_regmap.json: $(LLRF_SHELL_SRC)
	mkdir -p $(AUTOGEN_DIR)
	$(PYTHON) $(BUILD_DIR)/reverse_json.py $< > $@

$(MODULE).json: $(AUTOGEN_DIR)/regmap_$(MODULE).json $(AUTOGEN_DIR)/scalar_$(MODULE)_regmap.json static_regmap.json
	$(PYTHON) $(BUILD_DIR)/merge_json.py -o $@ -i $^

$(MODULE)_expand.v: $(LLRF_SHELL_SRC) $(AUTOGEN_DIR)/$(MODULE)_auto.vh $(AUTOGEN_DIR)/addr_map_$(MODULE).vh cordicg_b22.v
	$(VERILOG) $(VFLAGS_DEP) -E -o $@ $(LLRF_SHELL_SRC)

clean::
	rm -rf $(AUTOGEN_DIR) $(DEPDIR) $(MODULE)_expand.v $(MODULE).json cordicg_b22.v
