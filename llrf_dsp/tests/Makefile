include ../../dir_list.mk
include $(TOP)settings.mk

SIM ?= verilator

ifeq ($(SIM), icarus)
	COMPILE_ARGS += -Wall -Wno-timescale
	WAVES = 1
endif
ifeq ($(SIM), verilator)
	COMPILE_ARGS += --timing
# to avoid warning on 1-bit signal in counter
	EXTRA_ARGS += -Wno-width
# to avoid warning on unconnected output pins
	EXTRA_ARGS += -Wno-pinmissing
	EXTRA_ARGS += --trace-fst --trace-structs
endif

TOPLEVEL = dsp_core
MODULE   = test_dsp_core
TESTCASE = test_alsu,test_uspas,test_lemp

VERILOG_SOURCES += $(APP_DSP_DIR)/settings.vams
VERILOG_SOURCES += $(DSP_DIR)/dpram.v $(DSP_DIR)/fiq_interp.v \
					$(DSP_DIR)/flevel_set.v \
					$(DSP_DIR)/fwashout.v \
					$(DSP_DIR)/ph_acc.v \
					$(CORDIC_DIR)/addsubg.v $(CORDIC_DIR)/cstageg.v \
					$(APP_DSP_DIR)/cordicg_b22.v \
					$(APP_DSP_DIR)/dsp_core.v \
					$(APP_DSP_DIR)/noniq_ddc.v \
					$(APP_DSP_DIR)/pi_scalar.v

# https://github.com/cocotb/cocotb/issues/2279
# Check if testing failed message exists in results.xml.
.PHONY: check_results
check_results:
	-$(MAKE) all
	$(call check_for_results_file)
	python3 check_results.py

include $(shell cocotb-config --makefiles)/Makefile.sim

$(APP_DSP_DIR)/cordicg_b22.v: $(CORDIC_DIR)/cordicgx.py
	python3 $< 22 $@

clean::
	rm -f results.xml
	rm -rf __pycache__
