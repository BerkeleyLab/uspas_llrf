include ../../../../dir_list.mk
include $(TOP)settings.mk

DUT      = fiducial_int_gen
COCOTB_TOPLEVEL       = $(DUT)
COCOTB_TEST_MODULES   = test_$(DUT)

VERILOG_SOURCES += $(DESIGNS_DIR)/lemp/$(DUT).v
VERILOG_SOURCES += $(DSP_DIR)/freq_gcount.v
VERILOG_SOURCES += $(DSP_DIR)/reg_tech_cdc.v

include $(APP_DSP_DIR)/tests/cocotb_inc.mk
