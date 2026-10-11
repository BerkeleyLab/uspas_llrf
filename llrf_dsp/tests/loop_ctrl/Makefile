include ../../../dir_list.mk
include $(TOP)settings.mk

DUT      = loop_ctrl
COCOTB_TOPLEVEL       = $(DUT)
COCOTB_TEST_MODULES   = test_$(DUT)

VERILOG_SOURCES += $(DSP_DIR)/dpram.v \
                   $(CORDIC_DIR)/addsubg.v $(CORDIC_DIR)/cstageg.v \
                   cordicg_b22.v \
                   $(APP_DSP_DIR)/pi_scalar.v \
                   $(APP_DSP_DIR)/dsp_core.v \
                   $(APP_DSP_DIR)/pulse_gen.v \
                   $(APP_DSP_DIR)/$(DUT).v

include ../cocotb_inc.mk

cordicg_b22.v: $(CORDIC_DIR)/cordicgx.py
	python3 $< 22 $@

clean::
	rm -f cordicg_b22.v
