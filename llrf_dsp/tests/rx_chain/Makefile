include ../../../dir_list.mk
include $(TOP)settings.mk

DUT      = rx_chain
COCOTB_TOPLEVEL       = test_$(DUT)
COCOTB_TEST_MODULES   = test_$(DUT)

VERILOG_SOURCES += $(APP_DSP_DIR)/llrf_shell_pkg.sv
VERILOG_SOURCES += $(CORDIC_DIR)/addsubg.v $(CORDIC_DIR)/cstageg.v
VERILOG_SOURCES += cordicg_b22.v \
                   $(APP_DSP_DIR)/ph_acc_general.v \
                   $(APP_DSP_DIR)/dds.v
VERILOG_SOURCES += $(DSP_DIR)/fiq_interp.v \
                   $(DSP_DIR)/fwashout.v \
                   $(APP_DSP_DIR)/ddc.v \
                   $(APP_DSP_DIR)/noniq_ddc.v
VERILOG_SOURCES += $(APP_DSP_DIR)/$(DUT).sv test_$(DUT).sv

include ../cocotb_inc.mk

cordicg_b22.v: $(CORDIC_DIR)/cordicgx.py
	python3 $< 22 $@

clean::
	rm -f cordicg_b22.v
