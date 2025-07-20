include ../../../dir_list.mk
include $(TOP)settings.mk

DUT      = duc
TOPLEVEL = test_$(DUT)
MODULE   = test_$(DUT)

VERILOG_SOURCES += $(DSP_DIR)/cpxmul_fullspeed.v \
                   $(DSP_DIR)/data_xdomain.v $(DSP_DIR)/reg_tech_cdc.v $(DSP_DIR)/flag_xdomain.v \
                   $(DSP_DIR)/serializer_multichannel.v $(DSP_DIR)/serialize.v
VERILOG_SOURCES += test_$(DUT).sv $(APP_DSP_DIR)/dac_interp.v $(APP_DSP_DIR)/interpolator.v

# module parameters
export PARAM_DWI  := 18
export PARAM_DW   := 16
export PARAM_DWLO := 18

include ../cocotb_inc.mk
