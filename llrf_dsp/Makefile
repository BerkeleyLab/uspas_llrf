include ../dir_list.mk
include $(TOP)settings.mk
include $(BUILD_DIR)/top_rules.mk
include $(BUILD_DIR)/newad_top_rules.mk
include $(CORDIC_DIR)/rules.mk

vpath %.v $(DSP_DIR)
VFLAGS_DEP += -y$(DSP_DIR) -y$(CORDIC_DIR) -y$(SERIAL_IO_DIR)/EVG_EVR -y.
VFLAGS_DEP += -I$(AUTOGEN_DIR) -y$(AUTOGEN_DIR)
VFLAGS_DEP += -I$(BEDROCK_DIR)/localbus -y$(BEDROCK_DIR)/localbus
VFLAGS += $(VFLAGS_DEP)
VFLAGS += -g2012

.DEFAULT_GOAL = all
.PHONY: all clean
all: llrf_shell_expand.v
	$(MAKE) -C tests FSET=$(FSET)

llrf_shell_expand.v: cordicg_b22.v

##### others #####
include build.mk

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
