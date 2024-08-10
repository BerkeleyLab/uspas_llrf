include ../dir_list.mk
include $(BUILD_DIR)/top_rules.mk
IP_NAME = marble_bsp
# TARGET  = $(IP_NAME)_expand.v
TEST_BENCH  = $(IP_NAME)_tb

vpath %.v $(DSP_DIR)
VFLAGS_DEP += -I$(BADGER_DIR) -y$(BADGER_DIR)
VFLAGS_DEP += -I$(SERIAL_IO_DIR) -y$(SERIAL_IO_DIR) -y$(DSP_DIR) -y.
VFLAGS_DEP += -y$(FPGA_FAMILY_DIR)/xilinx
VFLAGS_DEP += -y$(PROJECTS_DIR)/test_marble_family -y$(BADGER_DIR)/tests -y$(HOMELESS_DIR)
VFLAGS += $(VFLAGS_DEP)
VFLAGS += -g2012

.PHONY: all
all: $(TEST_BENCH)

VERILOG_AUTOGEN  += $(RTEFI_V)
RTEFI_CLIENT_LIST = hello.v speed_test.v lb_gateway.v
include $(BADGER_DIR)/rules.mk

$(DEPDIR)/$(IP_NAME).d: marble_bsp.v $(VERILOG_AUTOGEN)
	@set -e;
	mkdir -p $(DEPDIR);
	$(MAKEDEP) && (printf "$(IP_NAME)_expand.v $@: "; \
	sort -ur $@.$$$$ | tr '\n' ' '; printf "\n" ) > $@ && rm -f $@.$$$$

# this is to avoid vivado critical warnings about duplicated / redefination of module since they are already in DSP
EXCLUDE = $(wildcard $(FPGA_FAMILY_DIR)/xilinx/*.v)
EXCLUDE += $(addprefix $(DSP_DIR)/, reg_delay.v dpram.v reg_tech_cdc.v)
$(IP_NAME)_expand.v: $(IP_NAME).v
	$(VERILOG) $(VFLAGS_DEP) -E -o $@ $(filter-out $(EXCLUDE),$(filter %.v, $^))

ifneq (,$(findstring _tb,$(MAKECMDGOALS)))
    -include $(MAKECMDGOALS:%_tb=$(DEPDIR)/%_tb.d)
endif
ifeq (,$(MAKECMDGOALS))
    -include $(DEPDIR)/$(IP_NAME).d
    -include $(TEST_BENCH_D)
endif

CLEAN += $(TEST_BENCH)
CLEAN += $(IP_NAME)_expand.v
CLEAN += $(RTEFI_CLEAN) $(TARGET)
include $(BUILD_DIR)/bottom_rules.mk
