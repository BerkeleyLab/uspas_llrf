include ../dir_list.mk
include $(TOP)settings.mk
include $(BUILD_DIR)/top_rules.mk
include $(BUILD_DIR)/newad_top_rules.mk

IP_NAME     = marble_bsp
LB_AW       = 17    # should be LB_HI
NEWAD_ARGS += -m    # mirror
NEWAD_ARGS_marble_bsp = -b262144
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
VFLAGS_DEP += $(SYNTH_OPT)
VFLAGS += $(VFLAGS_DEP)
VFLAGS += -g2012

.DEFAULT_GOAL = all
.PHONY: all clean
all: $(TEST_BENCH) $(CHECKS)

##### build.mk
TEST_BENCH_D      = $(TEST_BENCH:%_tb=$(DEPDIR)/%_tb.d)
VERILOG_AUTOGEN  += settings.vams
VERILOG_AUTOGEN  += $(AUTOGEN_DIR)/$(IP_NAME)_auto.vh $(AUTOGEN_DIR)/addr_map_$(IP_NAME).vh
VERILOG_AUTOGEN  += $(AUTOGEN_DIR)/regmap_$(IP_NAME).vh
RTEFI_CLIENT_LIST = hello.v speed_test.v lb_gateway.v spi_flash.v
include $(BADGER_DIR)/rules.mk
VERILOG_AUTOGEN  += $(RTEFI_V)

settings.vams: $(APP_DSP_DIR)/settings.json
	python3 $(APP_DSP_DIR)/scripts/gen_settings.py -f $< -c $(FSET) -o $@

$(DEPDIR)/$(IP_NAME)_tb.d:  $(VERILOG_AUTOGEN)

$(DEPDIR)/$(IP_NAME).d: $(IP_NAME).v $(VERILOG_AUTOGEN)
	set -e; mkdir -p $(DEPDIR); \
	$(MAKEDEP) && (printf "$(IP_NAME)_expand.v $@: "; \
	sort -ur $@.$$$$ | tr '\n' ' '; printf "\n" ) > $@ && rm -f $@.$$$$

$(AUTOGEN_DIR)/%_expand.v: %.v $(AUTOGEN_DIR)/%_auto.vh $(AUTOGEN_DIR)/addr_map_%.vh
	$(VERILOG) $(VFLAGS_DEP) -E -o$@ $^
	sed -i '/^$$/d' $@

$(AUTOGEN_DIR)/regmap_%.vh: %.json
	mkdir -p $(AUTOGEN_DIR); \
	$(PYTHON) $(BEDROCK_DIR)/localbus/gen_regmap.py -i $< -o $@

$(AUTOGEN_DIR)/scalar_%_regmap.json: $(IP_NAME).v
	mkdir -p $(AUTOGEN_DIR); \
	$(PYTHON) $(BUILD_DIR)/reverse_json.py $< > $@

$(IP_NAME).json: $(AUTOGEN_DIR)/regmap_$(IP_NAME).json $(AUTOGEN_DIR)/scalar_$(IP_NAME)_regmap.json static_$(IP_NAME).json
	$(PYTHON) $(BUILD_DIR)/merge_json.py -o $@ -i $^

# this is to avoid vivado critical warnings about duplicated / redefination of module since they are already in DSP
EXCLUDE  = $(wildcard $(FPGA_FAMILY_DIR)/xilinx/*.v)
EXCLUDE += $(addprefix $(DSP_DIR)/, reg_delay.v dpram.v reg_tech_cdc.v flag_xdomain.v data_xdomain.v freq_gcount.v freq_count.v phase_diff.v phaset.v)
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
CLEAN += $(IP_NAME).json
CLEAN += settings.vams
CLEAN += evr_gtx/*.v evr_gtx/*.xdc evr_gtx/*.vhdl evr_gtx/*.xml evr_gtx/*.dcp evr_gtx/*.xml evr_gtx/*.veo
CLEAN_DIRS += evr_gtx/tcl evr_gtx/gtx_init evr_gtx/doc $(AUTOGEN_DIR)

include $(BUILD_DIR)/bottom_rules.mk
