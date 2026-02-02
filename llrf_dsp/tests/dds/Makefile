include ../../../dir_list.mk
include $(TOP)settings.mk

DUT      = dds
COCOTB_TOPLEVEL       = $(DUT)
COCOTB_TEST_MODULES   = test_$(DUT)

VERILOG_SOURCES += $(CORDIC_DIR)/addsubg.v $(CORDIC_DIR)/cstageg.v
VERILOG_SOURCES += cordicg_b22.v \
                   $(APP_DSP_DIR)/ph_acc_general.v \
                   $(APP_DSP_DIR)/dds.v

# module parameters
export PARAM_DWLO       := 18
export PARAM_DWH        := 20
export PARAM_DWL        := 12

include ../cocotb_inc.mk

cordicg_b22.v: $(CORDIC_DIR)/cordicgx.py
	python3 $< 22 $@

clean::
	rm -f cordicg_b22.v
