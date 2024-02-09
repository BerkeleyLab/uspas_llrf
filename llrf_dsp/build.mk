APP_NAME    = llrf_shell
JSON_DIR    = ./regmap
NEWAD_ARGS += -m    # mirror
NEWAD_ARGS_llrf_shell =-b196608

TEST_BENCH_D= $(TEST_BENCH:%_tb=$(DEPDIR)/%_tb.d)
VERILOG_AUTOGEN += $(AUTOGEN_DIR)/config_romx.v
VERILOG_AUTOGEN += $(AUTOGEN_DIR)/llrf_shell_auto.vh $(AUTOGEN_DIR)/addr_map_llrf_shell.vh
VERILOG_AUTOGEN += $(AUTOGEN_DIR)/regmap_llrf_shell.vh

$(TEST_BENCH_D):             cordicg_b22.v
$(DEPDIR)/$(APP_NAME)_tb.d:  $(VERILOG_AUTOGEN)

$(DEPDIR)/$(APP_NAME).d: $(APP_NAME).v $(VERILOG_AUTOGEN)
	@set -e; mkdir -p $(DEPDIR); \
	$(MAKEDEP) && (printf "$(APP_NAME)_expand.v $@: "; \
	sort -ur $@.$$$$ | tr '\n' ' '; printf "\n" ) > $@ && rm -f $@.$$$$

$(AUTOGEN_DIR)/%_expand.v: %.v $(AUTOGEN_DIR)/%_auto.vh $(AUTOGEN_DIR)/addr_map_%.vh
	$(VERILOG) $(VFLAGS_DEP) -E -o $@ $^
	sed -i '/^$$/d' $@

$(AUTOGEN_DIR)/regmap_%.vh: %.json
	$(PYTHON) $(JSON_DIR)/gen_regmap.py -i $< -o $@

$(AUTOGEN_DIR)/config_romx.v: $(APP_NAME).json
	$(PYTHON) $(BUILD_DIR)/build_rom.py -v $@ -j $<

$(APP_NAME).json: $(AUTOGEN_DIR)/regmap_$(APP_NAME).json $(AUTOGEN_DIR)/scalar_$(APP_NAME)_regmap.json $(JSON_DIR)/static_regmap.json
	$(PYTHON) $(BUILD_DIR)/merge_json.py -o $@ -i $^

$(AUTOGEN_DIR)/scalar_%_regmap.json: %.v
	$(PYTHON) $(BUILD_DIR)/reverse_json.py $< > $@

$(APP_NAME)_expand.v: $(APP_NAME).v
	$(VERILOG) $(VFLAGS_DEP) -E $(filter %.v, $^) -o $@

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
CLEAN += $(APP_NAME).json $(APP_NAME)_init_regs.json
CLEAN += $(APP_NAME)_expand.v
