include ../dir_list.mk
include $(TOP)settings.mk
include $(BUILD_DIR)/top_rules.mk
include $(BUILD_DIR)/newad_top_rules.mk
include $(APP_DSP_DIR)/rules.mk

.PHONY: clean all

.DEFAULT_GOAL := all

all: llrf_shell_expand.v
	$(MAKE) -C tests FSET=$(FSET)

# =====
# check of basic CDC-correctness
# rewrite the following rule from top_rules.mk to avoid depending directly on llrf_shell.v (%.v)
SHELL_EXTRA_V = $(DSP_DIR)/half_filt.v $(DSP_DIR)/sat_add.v
llrf_shell_yosys.json: llrf_shell_skin.v llrf_shell_expand.v $(SHELL_EXTRA_V) $(BUILD_DIR)/cdc_snitch_proc.ys
	$(YOSYS_JSON_PRECHECK)
	$(YOSYS) --version
	$(YOSYS) $(YOSYS_QUIET) -p "read_verilog $(YOSYS_JSON_OPTION) $(filter %.v, $^); script $(filter %_proc.ys, $^); write_json $@"
# exercise with make llrf_shell_expand.v llrf_shell_cdc.txt

CLEAN += llrf_shell_yosys.json llrf_shell_cdc.txt

clean::
	$(MAKE) -C tests clean
include $(BUILD_DIR)/bottom_rules.mk
