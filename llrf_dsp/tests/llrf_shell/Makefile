include ../../../dir_list.mk
include $(TOP)settings.mk

DUT      = llrf_shell
TOPLEVEL = test_$(DUT)
MODULE   = test_$(DUT)

VERILOG_SOURCES += $(APP_DSP_DIR)/llrf_shell_expand.v
VERILOG_SOURCES += test_$(DUT).sv
CUSTOM_SIM_DEPS += $(APP_DSP_DIR)/llrf_shell.json

# module parameters
export PARAM_CBUF_AW     := 6
export PARAM_SIG_BUF_AW  := 6
export PARAM_CBUF_DW     := 24
include ../cocotb_inc.mk

$(APP_DSP_DIR)/llrf_shell_expand.v:
	$(MAKE) -C $(dir $@) $(notdir $@)

$(APP_DSP_DIR)/llrf_shell.json:
	$(MAKE) -C $(dir $@) $(notdir $@)

