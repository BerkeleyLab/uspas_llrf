include ../../../dir_list.mk
include $(TOP)settings.mk

DUT      = cic_bpm
COCOTB_TOPLEVEL       = test_$(DUT)
COCOTB_TEST_MODULES   = test_$(DUT)

COMPILE_ARGS += -DSIMULATE

VERILOG_SOURCES +=  test_$(DUT).sv
VERILOG_SOURCES +=  $(DSP_DIR)/reg_delay.v \
                    $(DSP_DIR)/fiq_interp.v $(DSP_DIR)/fwashout.v \
                    $(CORDIC_DIR)/addsubg.v $(CORDIC_DIR)/cstageg.v

VERILOG_SOURCES +=  $(APP_DSP_DIR)/$(DUT).v
VERILOG_SOURCES +=  $(APP_DSP_DIR)/cic_mag3.v
VERILOG_SOURCES +=  $(APP_DSP_DIR)/cic_simple2.v
VERILOG_SOURCES +=  $(APP_DSP_DIR)/positionCalc.v
VERILOG_SOURCES +=  $(APP_DSP_DIR)/cic_timing.v
VERILOG_SOURCES +=  $(APP_DSP_DIR)/dds.v \
                    $(APP_DSP_DIR)/ddc.v \
                    $(APP_DSP_DIR)/noniq_ddc.v \
                    $(APP_DSP_DIR)/ph_acc_general.v
VERILOG_SOURCES +=  cordicg_b22.v

include ../cocotb_inc.mk

cordicg_b22.v: $(CORDIC_DIR)/cordicgx.py
	python3 $< 22 $@

clean::
	rm -f cordicg_b22.v