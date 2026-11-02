include ../../../../dir_list.mk
include $(TOP)settings.mk

DUT      = timing_core_local
COCOTB_TOPLEVEL       = $(DUT)
COCOTB_TEST_MODULES   = test_$(DUT)

VERILOG_SOURCES += $(DESIGNS_DIR)/lemp/$(DUT).v $(DESIGNS_DIR)/lemp/fiducial_int_gen.v
VERILOG_SOURCES += $(SERIAL_IO_DIR)/EVG_EVR/tinyEVR.v $(SERIAL_IO_DIR)/EVG_EVR/evr_ts_cdc.v
VERILOG_SOURCES += $(DSP_DIR)/flag_xdomain.v $(DSP_DIR)/freq_gcount.v $(DSP_DIR)/reg_tech_cdc.v
VERILOG_SOURCES += $(DSP_DIR)/data_xdomain.v

# the LEMP shell's event codes: ACCL, STBY, fiducial, TS1&4
export PARAM_DSP_EV1 := 151
export PARAM_DSP_EV2 := 152
export PARAM_DSP_EV3 := 1
export PARAM_DSP_EV4 := 10
export PARAM_EVR_TRIG_WINDOW := 200  # LEMP: 23800, shortened for sim

include $(APP_DSP_DIR)/tests/cocotb_inc.mk
