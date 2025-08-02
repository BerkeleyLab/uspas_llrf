APP_NAME    = llrf_shell
JSON_DIR    = ./regmap
LB_AW       = 17    # should be LB_HI
NEWAD_ARGS += -m    # mirror
NEWAD_ARGS_llrf_shell = -b69632  # 0x11000
FSET       ?= USPAS

VERILOG_AUTOGEN += settings.vams
VERILOG_AUTOGEN += $(AUTOGEN_DIR)/llrf_shell_auto.vh $(AUTOGEN_DIR)/addr_map_llrf_shell.vh

settings.vams: settings.json
	python3 scripts/gen_settings.py -f $< -c $(FSET) -o $@

$(DEPDIR)/$(APP_NAME).d: $(APP_NAME).v $(VERILOG_AUTOGEN) cordicg_b22.v
	@set -e; mkdir -p $(DEPDIR); \
	$(MAKEDEP) && (printf "$(APP_NAME)_expand.v $@: "; \
	sort -ur $@.$$$$ | tr '\n' ' '; printf "\n" ) > $@ && rm -f $@.$$$$

$(AUTOGEN_DIR)/%_expand.v: %.v $(AUTOGEN_DIR)/%_auto.vh $(AUTOGEN_DIR)/addr_map_%.vh
	$(VERILOG) $(VFLAGS_DEP) -E -o$@ $^
	sed -i '/^$$/d' $@

$(APP_NAME).json: $(AUTOGEN_DIR)/regmap_$(APP_NAME).json $(AUTOGEN_DIR)/scalar_$(APP_NAME)_regmap.json $(JSON_DIR)/static_regmap.json
	$(PYTHON) $(BUILD_DIR)/merge_json.py -o $@ -i $^

$(AUTOGEN_DIR)/scalar_%_regmap.json: %.v
	mkdir -p $(AUTOGEN_DIR); \
	$(PYTHON) $(BUILD_DIR)/reverse_json.py $< > $@

$(APP_NAME)_expand.v: $(APP_NAME).v
	$(VERILOG) $(VFLAGS_DEP) -E -o $@ $(filter %.v, $^)

$(APP_NAME)_init_regs.json: settings.json
	$(PYTHON) llrf_model/llrf_dsp.py -c $(FSET) -f $< -o $@

ifneq (,$(findstring json,$(MAKECMDGOALS)))
    -include $(DEPDIR)/$(APP_NAME).d
endif
ifneq (,$(findstring _expand,$(MAKECMDGOALS)))
    -include $(DEPDIR)/$(APP_NAME).d
endif
ifeq (,$(MAKECMDGOALS))
    -include $(DEPDIR)/$(APP_NAME).d
endif
CLEAN += settings.vams
CLEAN += $(APP_NAME).json $(APP_NAME)_init_regs.json
CLEAN += $(APP_NAME)_expand.v
CLEAN += cordicg_b22.v
