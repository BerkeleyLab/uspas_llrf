include ../../dir_list.mk
include $(TOP)settings.mk
include $(BUILD_DIR)/top_rules.mk
SHELL_SRC = ../uspas/llrf_shell.sv
include $(DESIGNS_DIR)/rules.mk
clean::
	$(MAKE) -C tb/llrf_shell clean

include $(BUILD_DIR)/bottom_rules.mk
