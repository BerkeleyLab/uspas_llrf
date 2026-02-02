include ../../../dir_list.mk
include $(TOP)settings.mk

DUT      = ddc
COCOTB_TOPLEVEL       = $(DUT)
COCOTB_TEST_MODULES   = test_$(DUT)

VERILOG_SOURCES += $(DSP_DIR)/fiq_interp.v \
                   $(DSP_DIR)/fwashout.v
VERILOG_SOURCES += $(APP_DSP_DIR)/ddc.v \
                   $(APP_DSP_DIR)/noniq_ddc.v

# module parameters
export PARAM_DWI  := 16
export PARAM_DWO  := 18
export PARAM_DWLO := 18

include ../cocotb_inc.mk
