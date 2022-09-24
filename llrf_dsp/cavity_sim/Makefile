include ../../dir_list.mk
include $(BUILD_DIR)/top_rules.mk
include $(CORDIC_DIR)/rules.mk

VLATOR_ARGS = -Wno-PINMISSING -Wno-WIDTH -Wno-UNUSED
.PHONY: all dsp_core_wrapper_check clean
all: dsp_core_wrapper_check

##### dsp_core #####
obj_dir/Vdsp_core_wrapper: dsp_core_check.cpp dsp_core_wrapper.v ../dsp_core.v cordicg_b22.v ../fdownconvert_als.v ../pi_scalar.v
	$(VERILATOR) --trace $(VLATOR_ARGS) -cc --timescale-override 1ns/1ns\
		--exe -I$. -I$(CORDIC_DIR) -I$(DSP_DIR) -I.. $^
	MAKEFLAGS="" $(MAKE) -C $(dir $@) -f $(notdir $@).mk

dsp_core_wrapper.dat dsp_core_wrapper.vcd:  obj_dir/Vdsp_core_wrapper
	$< +vcd

dsp_core_wrapper_check: obj_dir/Vdsp_core_wrapper
	@echo "### Checking $@ ..."
	@$<
	python3 verify_sim.py

CLEAN_DIRS += obj_dir
CLEAN += *.dat
CLEAN += *.vcd
CLEAN += cordicg_b22.v
include $(BUILD_DIR)/bottom_rules.mk