include ../dir_list.mk
include $(BUILD_DIR)/top_rules.mk
include $(CORDIC_DIR)/rules.mk
LB_AW       = 17    # should be LB_HI
TEST_BENCH  = llrf_shell_tb noniq_ddc_tb dsp_core_tb
CHECKS      = noniq_ddc_check dsp_core_check llrf_shell_check

vpath %.v $(DSP_DIR) $(SERIAL_IO_DIR)/EVG_EVR
VFLAGS_DEP += -y$(DSP_DIR) -y$(CORDIC_DIR) -y$(SERIAL_IO_DIR)/EVG_EVR -y.
VFLAGS_DEP += -I$(AUTOGEN_DIR) -y$(AUTOGEN_DIR)
VFLAGS += $(VFLAGS_DEP)

.PHONY: all clean# $(CHECKS)
all: $(TEST_BENCH) $(CHECKS)

##### others #####
include build.mk

CLEAN += $(TEST_BENCH)
CLEAN += xvlog.log xvlog.pb
CLEAN += cordicg_b22.v
CLEAN_DIRS += xsim.dir
CLEAN += $(TEST_BENCH:%_tb=%.vcd)

include $(BUILD_DIR)/bottom_rules.mk
