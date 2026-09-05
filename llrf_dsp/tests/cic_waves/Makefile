include ../../../dir_list.mk
include $(TOP)settings.mk

DUT      = cic_waves
COCOTB_TOPLEVEL       = test_$(DUT)
COCOTB_TEST_MODULES   = test_$(DUT)

VERILOG_SOURCES +=  test_$(DUT)_pkg.sv
VERILOG_SOURCES +=  $(DSP_DIR)/dpram.v
VERILOG_SOURCES +=  test_$(DUT).sv
VERILOG_SOURCES +=  $(DSP_DIR)/cic_wave_recorder.v
VERILOG_SOURCES +=  $(DSP_DIR)/circle_buf_serial.v
VERILOG_SOURCES +=  $(DSP_DIR)/circle_buf.v
VERILOG_SOURCES +=  $(DSP_DIR)/cic_multichannel.v
VERILOG_SOURCES +=  $(DSP_DIR)/serializer_multichannel.v
VERILOG_SOURCES +=  $(DSP_DIR)/serialize.v
VERILOG_SOURCES +=  $(DSP_DIR)/ccfilt.v
VERILOG_SOURCES +=  $(DSP_DIR)/reg_tech_cdc.v
VERILOG_SOURCES +=  $(DSP_DIR)/doublediff.v
VERILOG_SOURCES +=  $(DSP_DIR)/double_inte_smp.v
VERILOG_SOURCES +=  $(DSP_DIR)/reg_delay.v
VERILOG_SOURCES +=  $(DSP_DIR)/minmax.v
VERILOG_SOURCES +=  $(DSP_DIR)/timestamp.v
VERILOG_SOURCES +=  $(DSP_DIR)/fchan_subset.v
VERILOG_SOURCES +=  $(DSP_DIR)/demand_gpt.v

VERILOG_SOURCES +=  $(APP_DSP_DIR)/pulse_gen.v
VERILOG_SOURCES +=  $(APP_DSP_DIR)/cic_waves.v
VERILOG_SOURCES +=  $(APP_DSP_DIR)/cic_timing.v
VERILOG_SOURCES +=  $(APP_DSP_DIR)/slow_bridge_shell.v

# module parameters
export PARAM_CBUF_AW  := 6

include ../cocotb_inc.mk
