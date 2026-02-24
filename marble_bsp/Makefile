include ../dir_list.mk
include $(TOP)settings.mk
include $(BUILD_DIR)/top_rules.mk
include $(BUILD_DIR)/newad_top_rules.mk

IP_NAME     = marble_bsp
LB_AW       = 17    # should be LB_HI
NEWAD_ARGS += -m    # mirror
NEWAD_ARGS_marble_bsp = -b262144
NEWAD_DIRS = .,$(DSP_DIR)/hosted
TEST_BENCH  = $(IP_NAME)_tb
CHECKS      = $(IP_NAME)_check

vpath %.v $(DSP_DIR) $(DSP_DIR)/hosted
VFLAGS_DEP += -I$(BADGER_DIR) -y$(BADGER_DIR)
VFLAGS_DEP += -I$(SERIAL_IO_DIR) -y$(SERIAL_IO_DIR) -y$(DSP_DIR) -y.
VFLAGS_DEP += -I$(DSP_DIR)/hosted -y$(DSP_DIR)/hosted
VFLAGS_DEP += -y$(FPGA_FAMILY_DIR)/xilinx
VFLAGS_DEP += -y$(AUTOGEN_DIR) -I$(AUTOGEN_DIR)
VFLAGS_DEP += -y$(PICORV_DIR)/gateware  # for spi_engine.v
VFLAGS_DEP += -I$(BEDROCK_DIR)/localbus -y$(BEDROCK_DIR)/localbus
VFLAGS_DEP += -I$(SERIAL_IO_DIR)/EVG_EVR -y$(SERIAL_IO_DIR)/EVG_EVR
VFLAGS_DEP += -y$(PROJECTS_DIR)/test_marble_family -y$(BADGER_DIR)/tests -y$(HOMELESS_DIR)
VFLAGS_DEP += $(SYNTH_OPT)
VFLAGS += $(VFLAGS_DEP)
VFLAGS += -g2012

.DEFAULT_GOAL = all
.PHONY: all clean
all: $(TEST_BENCH) $(CHECKS)

##### build.mk
TEST_BENCH_D      = $(TEST_BENCH:%_tb=$(DEPDIR)/%_tb.d)

include build.mk

ifneq (,$(findstring _tb,$(MAKECMDGOALS)))
    -include $(MAKECMDGOALS:%_tb=$(DEPDIR)/%_tb.d)
endif
ifneq (,$(findstring vcd,$(MAKECMDGOALS)))
    -include $(MAKECMDGOALS:%.vcd=$(DEPDIR)/%_tb.d)
endif
ifneq (,$(findstring _check,$(MAKECMDGOALS)))
    -include $(MAKECMDGOALS:%_check=$(DEPDIR)/%_tb.d)
endif
ifneq (,$(findstring _expand,$(MAKECMDGOALS)))
    -include $(DEPDIR)/$(IP_NAME).d
    -include $(TEST_BENCH_D)
endif
ifeq (,$(MAKECMDGOALS))
    -include $(DEPDIR)/$(IP_NAME).d
    -include $(TEST_BENCH_D)
endif

CLEAN += $(TEST_BENCH)
CLEAN += $(RTEFI_CLEAN)

include $(BUILD_DIR)/bottom_rules.mk
