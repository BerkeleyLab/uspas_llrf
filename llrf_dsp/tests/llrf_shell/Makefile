include ../../../dir_list.mk
include $(TOP)settings.mk

DUT      = llrf_shell
TOPLEVEL = $(DUT)
MODULE   = test_$(DUT)

VERILOG_SOURCES += $(APP_DSP_DIR)/llrf_shell_expand.v

# module parameters
include ../cocotb_inc.mk

$(APP_DSP_DIR)/llrf_shell_expand.v:
	make -C $(APP_DSP_DIR) llrf_shell_expand.v
