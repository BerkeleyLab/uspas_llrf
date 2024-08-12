include ../dir_list.mk
include $(BUILD_DIR)/top_rules.mk

IP_NAME     = marble_bsp
TEST_BENCH  = $(IP_NAME)_tb
CHECKS      = $(IP_NAME)_check

vpath %.v $(DSP_DIR)
VFLAGS_DEP += -I$(BADGER_DIR) -y$(BADGER_DIR)
VFLAGS_DEP += -I$(SERIAL_IO_DIR) -y$(SERIAL_IO_DIR) -y$(DSP_DIR) -y.
VFLAGS_DEP += -y$(FPGA_FAMILY_DIR)/xilinx
VFLAGS_DEP += -I$(AUTOGEN_DIR) -y$(AUTOGEN_DIR)
VFLAGS_DEP += -y$(PICORV_DIR)/gateware  # for spi_engine.v
VFLAGS_DEP += -I$(BEDROCK_DIR)/localbus -y$(BEDROCK_DIR)/localbus
VFLAGS_DEP += -y$(PROJECTS_DIR)/test_marble_family -y$(BADGER_DIR)/tests -y$(HOMELESS_DIR)
VFLAGS += $(VFLAGS_DEP)
VFLAGS += -g2012

.DEFAULT_GOAL = all
.PHONY: all clean
all: $(TEST_BENCH) $(CHECKS)

##### build.mk
TEST_BENCH_D      = $(TEST_BENCH:%_tb=$(DEPDIR)/%_tb.d)
VERILOG_AUTOGEN  += $(AUTOGEN_DIR)/regmap_$(IP_NAME).vh
RTEFI_CLIENT_LIST = hello.v speed_test.v lb_gateway.v
include $(BADGER_DIR)/rules.mk
VERILOG_AUTOGEN  += $(RTEFI_V)

$(DEPDIR)/$(IP_NAME)_tb.d:  $(VERILOG_AUTOGEN)

$(AUTOGEN_DIR)/regmap_%.vh: %.json
	mkdir -p $(AUTOGEN_DIR); \
	$(PYTHON) $(BEDROCK_DIR)/localbus/gen_regmap.py -i $< -o $@

$(DEPDIR)/$(IP_NAME).d: $(IP_NAME).v $(VERILOG_AUTOGEN)
	@set -e; mkdir -p $(DEPDIR); \
	$(MAKEDEP) && (printf "$(IP_NAME)_expand.v $@: "; \
	sort -ur $@.$$$$ | tr '\n' ' '; printf "\n" ) > $@ && rm -f $@.$$$$

# this is to avoid vivado critical warnings about duplicated / redefination of module since they are already in DSP
EXCLUDE  = $(wildcard $(FPGA_FAMILY_DIR)/xilinx/*.v)
EXCLUDE += $(addprefix $(DSP_DIR)/, reg_delay.v dpram.v reg_tech_cdc.v)
$(IP_NAME)_expand.v: $(IP_NAME).v #$(DEPDIR)/$(IP_NAME).d
	$(VERILOG) $(VFLAGS_DEP) -E -o $@ $(filter-out $(EXCLUDE),$(filter %.v, $^))

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
CLEAN += $(IP_NAME)_expand.v
CLEAN += $(RTEFI_CLEAN)
include $(BUILD_DIR)/bottom_rules.mk
