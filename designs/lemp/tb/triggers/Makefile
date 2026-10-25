include ../../../../dir_list.mk
include $(TOP)settings.mk

DUT      = triggers
COCOTB_TOPLEVEL       = $(DUT)
COCOTB_TEST_MODULES   = test_$(DUT)

VERILOG_SOURCES += $(DESIGNS_DIR)/lemp/$(DUT).v

include $(APP_DSP_DIR)/tests/cocotb_inc.mk
