MODULE    = llrf_shell

# newad related: see bedrock/build-tools/newad_top_rules.mk
LB_AW       = 17    # should be LB_HI
NEWAD_ARGS += -m    # mirror
NEWAD_ARGS_llrf_shell = -b69632  # 0x11000
FSET       ?= USPAS

VERILOG_AUTOGEN += settings.vams
VERILOG_AUTOGEN += $(AUTOGEN_DIR)/llrf_shell_auto.vh $(AUTOGEN_DIR)/addr_map_llrf_shell.vh

settings.vams: settings.json
	$(PYTHON) llrf_model/llrf_dsp.py -c $(FSET) -f $< --write-verilog-header $@

$(MODULE)_init_regs.json: settings.json
	$(PYTHON) llrf_model/llrf_dsp.py -c $(FSET) -f $< --write-init-reg $@

$(DEPDIR)/$(MODULE).d: $(MODULE).v $(VERILOG_AUTOGEN) cordicg_b22.v
	@set -e; mkdir -p $(DEPDIR); \
	$(MAKEDEP) && (printf "$(MODULE)_expand.v $@: "; \
	sort -ur $@.$$$$ | tr '\n' ' '; printf "\n" ) > $@ && rm -f $@.$$$$

$(AUTOGEN_DIR)/%_expand.v: %.v $(AUTOGEN_DIR)/%_auto.vh $(AUTOGEN_DIR)/addr_map_%.vh
	$(VERILOG) $(VFLAGS_DEP) -E -o$@ $^
	sed -i '/^$$/d' $@

$(MODULE).json: $(AUTOGEN_DIR)/regmap_$(MODULE).json $(AUTOGEN_DIR)/scalar_$(MODULE)_regmap.json static_regmap.json
	$(PYTHON) $(BUILD_DIR)/merge_json.py -o $@ -i $^

$(AUTOGEN_DIR)/scalar_%_regmap.json: %.v
	mkdir -p $(AUTOGEN_DIR); \
	$(PYTHON) $(BUILD_DIR)/reverse_json.py $< > $@

$(MODULE)_expand.v: $(MODULE).v
	$(VERILOG) $(VFLAGS_DEP) -E -o $@ $(filter %.v, $^)

ifneq (,$(findstring json,$(MAKECMDGOALS)))
    -include $(DEPDIR)/$(MODULE).d
endif
ifneq (,$(findstring _expand,$(MAKECMDGOALS)))
    -include $(DEPDIR)/$(MODULE).d
endif
ifeq (,$(MAKECMDGOALS))
    -include $(DEPDIR)/$(MODULE).d
endif
CLEAN += settings.vams
CLEAN += $(MODULE).json $(MODULE)_init_regs.json
CLEAN += $(MODULE)_expand.v
CLEAN += cordicg_b22.v
