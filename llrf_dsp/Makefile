include ../dir_list.mk
include $(TOP)settings.mk
include $(BUILD_DIR)/top_rules.mk
include $(BUILD_DIR)/newad_top_rules.mk
include $(CORDIC_DIR)/rules.mk
TEST_BENCH  = llrf_shell_tb zest_dac_interp_tb
CHECKS      = llrf_shell_check zest_dac_interp_check

vpath %.v $(DSP_DIR)
VFLAGS_DEP += -y$(DSP_DIR) -y$(CORDIC_DIR) -y.
VFLAGS_DEP += -I$(AUTOGEN_DIR) -y$(AUTOGEN_DIR)
VFLAGS += $(VFLAGS_DEP)
VFLAGS += -g2012

.PHONY: all clean
all: $(TEST_BENCH) $(CHECKS)

##### others #####
include build.mk

CLEAN += $(TEST_BENCH)
CLEAN += xvlog.log xvlog.pb
CLEAN_DIRS += xsim.dir
CLEAN += tests/dump.fst tests/results.xml
CLEAN_DIRS += tests/sim_build tests/__pycache__
CLEAN += $(TEST_BENCH:%_tb=%.vcd)

include $(BUILD_DIR)/bottom_rules.mk