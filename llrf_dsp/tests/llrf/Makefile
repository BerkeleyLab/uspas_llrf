include ../../../dir_list.mk
include $(TOP)settings.mk

DUT      = llrf_dsp
TOPLEVEL = $(DUT)
MODULE   = test_$(DUT)
TESTCASE = test_alsu,test_uspas,test_lemp,test_awa

VERILOG_SOURCES += $(DSP_DIR)/dpram.v $(DSP_DIR)/fiq_interp.v \
                    $(DSP_DIR)/flevel_set.v \
                    $(DSP_DIR)/fwashout.v \
                    $(CORDIC_DIR)/addsubg.v $(CORDIC_DIR)/cstageg.v

VERILOG_SOURCES += cordicg_b22.v \
                    $(APP_DSP_DIR)/ph_acc_general.v \
                    $(APP_DSP_DIR)/llrf_dsp.v \
                    $(APP_DSP_DIR)/ddc.v \
                    $(APP_DSP_DIR)/dsp_core.v \
                    $(APP_DSP_DIR)/noniq_ddc.v \
                    $(APP_DSP_DIR)/pi_scalar.v

# module parameters
export PARAM_KW                 := 18
export PARAM_BASEBAND_INPUT     := 0

include ../cocotb_inc.mk

cordicg_b22.v: $(CORDIC_DIR)/cordicgx.py
	python3 $< 22 $@

clean::
	rm -f cordicg_b22.v
