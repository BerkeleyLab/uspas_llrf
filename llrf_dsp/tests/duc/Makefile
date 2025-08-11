include ../../../dir_list.mk
include $(TOP)settings.mk

DUT      = dac_duc
TOPLEVEL = $(DUT)
MODULE   = test_duc

VERILOG_SOURCES += $(DSP_DIR)/cpxmul_fullspeed.v \
                   $(DSP_DIR)/data_xdomain.v $(DSP_DIR)/reg_tech_cdc.v $(DSP_DIR)/flag_xdomain.v \
                   $(DSP_DIR)/serializer_multichannel.v $(DSP_DIR)/serialize.v \
                   $(DSP_DIR)/reg_delay.v
VERILOG_SOURCES += $(APP_DSP_DIR)/$(DUT).v $(APP_DSP_DIR)/interp_xdomain.v $(APP_DSP_DIR)/interpolator.v

# module parameters
export PARAM_DWI  := 18
export PARAM_DWO  := 16
export PARAM_DWLO := 18

include ../cocotb_inc.mk
