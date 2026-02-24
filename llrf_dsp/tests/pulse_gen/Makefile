include ../../../dir_list.mk
include $(TOP)settings.mk

DUT      = pulse_gen
COCOTB_TOPLEVEL       = $(DUT)
COCOTB_TEST_MODULES   = test_$(DUT)

VERILOG_SOURCES += $(APP_DSP_DIR)/$(DUT).v

# module parameters
export PARAM_AW  := 12

include ../cocotb_inc.mk
