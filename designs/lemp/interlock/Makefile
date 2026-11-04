# LEMP interlock (plan step 9d): interlock_wrapper, moved as-is from the LEMP
# branch (D23). It stays newad, on localbus segment 2; its JSON is merged into
# the config ROM by top/lemp (step 9e).
include ../../../dir_list.mk
include $(BUILD_DIR)/newad_top_rules.mk
include $(CORDIC_DIR)/rules.mk
DESIGN = lemp
include $(TOP)settings.mk
TEST_BENCH  = interlock_wrapper_tb
CHECKS      = interlock_wrapper_check

vpath %.v $(DSP_DIR)
VFLAGS_DEP += -y$(DSP_DIR) -y$(CORDIC_DIR) -y$(APP_DSP_DIR) -y.
VFLAGS_DEP += -I$(AUTOGEN_DIR) -y$(AUTOGEN_DIR)
VFLAGS_DEP += -I$(BEDROCK_DIR)/localbus -y$(BEDROCK_DIR)/localbus
VFLAGS += $(VFLAGS_DEP)
VFLAGS += -g2012

.DEFAULT_GOAL = all
.PHONY: all clean
all: $(TEST_BENCH) $(CHECKS)

##### others #####
include build.mk

# =====
# check of basic CDC-correctness: interlock_wrapper_expand.v leaves out the
# modules the top level already gets from llrf_shell_expand.v (EXCLUDE in
# build.mk), so the check reads interlock_wrapper_cdc_expand.v, which has them
interlock_wrapper_yosys.json: interlock_wrapper_skin.v interlock_wrapper_cdc_expand.v $(BUILD_DIR)/cdc_snitch_proc.ys
	$(YOSYS_JSON_PRECHECK)
	$(YOSYS) --version
	$(YOSYS) $(YOSYS_QUIET) -p "read_verilog $(YOSYS_JSON_OPTION) $(filter %.v, $^); script $(filter %_proc.ys, $^); write_json $@"
# exercise with make interlock_wrapper_cdc.txt

CLEAN += $(TEST_BENCH)
CLEAN += xvlog.log xvlog.pb
CLEAN += cordicg_b22.v
CLEAN += *.dat *.vcd
CLEAN_DIRS += xsim.dir
CLEAN += interlock_wrapper_yosys.json interlock_wrapper_cdc.txt interlock_wrapper_cdc_expand.v

include $(BUILD_DIR)/bottom_rules.mk
