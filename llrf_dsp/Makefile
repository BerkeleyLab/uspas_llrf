include ../dir_list.mk
include $(TOP)settings.mk
include $(BUILD_DIR)/top_rules.mk
include $(BUILD_DIR)/newad_top_rules.mk
include $(CORDIC_DIR)/rules.mk
TEST_BENCH  = llrf_shell_tb noniq_ddc_tb dsp_core_tb
CHECKS      = noniq_ddc_check dsp_core_check llrf_shell_check

vpath %.v $(DSP_DIR)
VFLAGS_DEP += -y$(DSP_DIR) -y$(CORDIC_DIR) -y.
VFLAGS_DEP += -I$(AUTOGEN_DIR) -y$(AUTOGEN_DIR)
VFLAGS += $(VFLAGS_DEP)

.PHONY: all clean
all: $(TEST_BENCH) $(CHECKS)

##### others #####
include build.mk

CLEAN += $(TEST_BENCH)
CLEAN += xvlog.log xvlog.pb
CLEAN_DIRS += xsim.dir
CLEAN += $(TEST_BENCH:%_tb=%.vcd)

include $(BUILD_DIR)/bottom_rules.mk
