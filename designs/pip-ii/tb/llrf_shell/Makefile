include ../../../../dir_list.mk
include $(TOP)settings.mk

DESIGN_DSP_DIR        = ../..
COCOTB_TOPLEVEL       = test_llrf_shell
COCOTB_TEST_MODULES   = test_llrf_shell

VERILOG_SOURCES += $(DESIGN_DSP_DIR)/llrf_shell_expand.v
VERILOG_SOURCES += $(APP_DSP_DIR)/test_llrf_shell.sv
CUSTOM_SIM_DEPS += $(DESIGN_DSP_DIR)/llrf_shell.json

# module parameters
export PARAM_CBUF_AW     := 6
export PARAM_SIG_BUF_AW  := 6
include  $(APP_DSP_DIR)/tests/cocotb_inc.mk

$(DESIGN_DSP_DIR)/llrf_shell_expand.v:
	$(MAKE) -C $(dir $@) $(notdir $@)

$(DESIGN_DSP_DIR)/llrf_shell.json:
	$(MAKE) -C $(dir $@) $(notdir $@)

clean::
	rm -f $(DESIGN_DSP_DIR)/llrf_shell_expand.v
	rm -f $(DESIGN_DSP_DIR)/llrf_shell.json