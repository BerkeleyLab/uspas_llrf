include ../../../../dir_list.mk
include $(TOP)settings.mk

DUT      = triggers
COCOTB_TOPLEVEL       = test_$(DUT)
COCOTB_TEST_MODULES   = test_$(DUT)

VERILOG_SOURCES += $(APP_DSP_DIR)/llrf_shell_pkg.sv
VERILOG_SOURCES += $(DESIGNS_DIR)/lemp/$(DUT).sv test_$(DUT).sv

include $(APP_DSP_DIR)/tests/cocotb_inc.mk
