include ../../../dir_list.mk
include $(TOP)settings.mk

DUT      = duc
TOPLEVEL = test_$(DUT)
MODULE   = test_$(DUT)

VERILOG_SOURCES += $(DSP_DIR)/cpxmul_fullspeed.v \
                   $(DSP_DIR)/data_xdomain.v $(DSP_DIR)/reg_tech_cdc.v $(DSP_DIR)/flag_xdomain.v \
                   $(ZEST_DIR)/zest_dac_interp.v
VERILOG_SOURCES += test_$(DUT).sv

# module parameters
export PARAM_DWI  := 18
export PARAM_DW   := 16
export PARAM_DWLO := 18

include ../cocotb_inc.mk
