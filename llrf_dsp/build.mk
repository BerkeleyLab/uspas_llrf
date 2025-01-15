APP_NAME    = llrf_shell
JSON_DIR    = ./regmap
LB_AW       = 17    # should be LB_HI
NEWAD_ARGS += -m    # mirror
NEWAD_ARGS_llrf_shell = -b69632  # 0x11000

TEST_BENCH_D= $(TEST_BENCH:%_tb=$(DEPDIR)/%_tb.d)
VERILOG_AUTOGEN += settings.vams
VERILOG_AUTOGEN += $(AUTOGEN_DIR)/llrf_shell_auto.vh $(AUTOGEN_DIR)/addr_map_llrf_shell.vh
VERILOG_AUTOGEN += $(AUTOGEN_DIR)/regmap_llrf_shell.vh

$(TEST_BENCH_D):             cordicg_b22.v
$(DEPDIR)/$(APP_NAME)_tb.d:  $(VERILOG_AUTOGEN)

settings.vams: settings.json
	python3 scripts/gen_settings.py -f $< -c $(FSET) -o $@

$(DEPDIR)/$(APP_NAME).d: $(APP_NAME).v $(VERILOG_AUTOGEN)
	@set -e; mkdir -p $(DEPDIR); \
	$(MAKEDEP) && (printf "$(APP_NAME)_expand.v $@: "; \
	sort -ur $@.$$$$ | tr '\n' ' '; printf "\n" ) > $@ && rm -f $@.$$$$

$(AUTOGEN_DIR)/%_expand.v: %.v $(AUTOGEN_DIR)/%_auto.vh $(AUTOGEN_DIR)/addr_map_%.vh
	$(VERILOG) $(VFLAGS_DEP) -E -o$@ $^
	sed -i '/^$$/d' $@

$(AUTOGEN_DIR)/regmap_%.vh: %.json
	mkdir -p $(AUTOGEN_DIR); \
	$(PYTHON) $(BEDROCK_DIR)/localbus/gen_regmap.py -i $< -o $@

$(APP_NAME).json: $(AUTOGEN_DIR)/regmap_$(APP_NAME).json $(AUTOGEN_DIR)/scalar_$(APP_NAME)_regmap.json $(JSON_DIR)/static_regmap.json
	$(PYTHON) $(BUILD_DIR)/merge_json.py -o $@ -i $^

$(AUTOGEN_DIR)/scalar_%_regmap.json: %.v
	mkdir -p $(AUTOGEN_DIR); \
	$(PYTHON) $(BUILD_DIR)/reverse_json.py $< > $@

$(APP_NAME)_expand.v: $(APP_NAME).v
	$(VERILOG) $(VFLAGS_DEP) -E -o $@ $(filter %.v, $^)

$(APP_NAME)_init_regs.json: $(APP_NAME)_tb
	$(VVP) $< $(VVP_FLAGS) +gen_init="$@"

ifneq (,$(findstring _tb,$(MAKECMDGOALS)))
    -include $(MAKECMDGOALS:%_tb=$(DEPDIR)/%_tb.d)
endif
ifneq (,$(findstring vcd,$(MAKECMDGOALS)))
    -include $(MAKECMDGOALS:%.vcd=$(DEPDIR)/%_tb.d)
endif
ifneq (,$(findstring _check,$(MAKECMDGOALS)))
    -include $(MAKECMDGOALS:%_check=$(DEPDIR)/%_tb.d)
endif
ifneq (,$(findstring json,$(MAKECMDGOALS)))
    -include $(DEPDIR)/$(APP_NAME).d
    -include $(TEST_BENCH_D)
endif
ifneq (,$(findstring _expand,$(MAKECMDGOALS)))
    -include $(DEPDIR)/$(APP_NAME).d
    -include $(TEST_BENCH_D)
endif
ifeq (,$(MAKECMDGOALS))
    -include $(DEPDIR)/$(APP_NAME).d
    -include $(TEST_BENCH_D)
endif
CLEAN += settings.vams
CLEAN += $(APP_NAME).json $(APP_NAME)_init_regs.json
CLEAN += $(APP_NAME)_expand.v
CLEAN += cordicg_b22.v
