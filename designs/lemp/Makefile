include ../../dir_list.mk
include $(TOP)settings.mk
include $(BUILD_DIR)/top_rules.mk
# LEMP shell (plan step 9c): the base blocks plus fiducial selection, PMOD
# triggers, phase shift, DAC permit latch, SSSB and timing_core_local
SHELL_SRC = llrf_shell.sv
DESIGN_SV_SRC = triggers.sv
DESIGN_LIB_SRC = fiducial_int_gen.v timing_core_local.v
include $(DESIGNS_DIR)/rules.mk
clean::
	$(MAKE) -C tb/llrf_shell clean

include $(BUILD_DIR)/bottom_rules.mk
