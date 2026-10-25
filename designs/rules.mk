# Common build rules and variables for LLRF DSP and Design modules
MODULE     = llrf_shell
GEN_DIR    = _gen
REGMAP_PY  = $(USPAS_LLRF_DIR)/regmap.py
DESIGN_PY  = $(wildcard design.py)
# the design shell (SystemVerilog): shared blocks, generated register file;
# designs that reuse the base shell set SHELL_SRC = ../uspas/llrf_shell.sv
SHELL_SRC ?= llrf_shell.sv
SV2V      ?= sv2v

.PHONY: all
all: $(MODULE)_expand.v $(MODULE).json

APP_DSP_SRC += slow_bridge_shell.v sig_buf.v pulse_gen.v pi_scalar.v ph_acc_general.v ntw_analyzer.v
APP_DSP_SRC += noniq_ddc.v monitor_inlk.v interp_xdomain.v interpolator.v
APP_DSP_SRC += dsp_core.v dds.v ddc.v dac_duc.v cic_waves.v cic_timing.v arc_inlk.v
APP_DSP_SRC += loop_ctrl.v
DSP_SRC     += timestamp.v serialize.v serializer_multichannel.v reg_tech_cdc.v reg_delay.v
DSP_SRC     += minmax.v fwashout.v freq_gcount.v freq_count.v flag_xdomain.v fiq_interp.v
DSP_SRC     += fchan_subset.v dpram.v double_inte_smp.v doublediff.v demand_gpt.v data_xdomain.v
DSP_SRC     += cpxmul_fullspeed.v circle_buf.v circle_buf_serial.v cic_wave_recorder.v cic_multichannel.v ccfilt.v
EVR_SRC     += tinyEVR.v timing_core.v evr_ts_cdc.v evrSROC.v
LIB_SRC  = $(addprefix $(APP_DSP_DIR)/, $(APP_DSP_SRC))
LIB_SRC += $(addprefix $(DSP_DIR)/, $(DSP_SRC))
LIB_SRC += $(addprefix $(SERIAL_IO_DIR)/EVG_EVR/, $(EVR_SRC))
LIB_SRC += $(BEDROCK_DIR)/cordic/cstageg.v $(BEDROCK_DIR)/cordic/addsubg.v
LIB_SRC += $(BEDROCK_DIR)/localbus/jit_rad_gateway.v
LIB_SRC += cordicg_b22.v

VFLAGS_DEP += -I$(GEN_DIR)
VFLAGS += -g2012

cordicg_b22.v:
	$(PYTHON) $(CORDIC_DIR)/cordicgx.py 22 $@

# rw registers, status words and readback mux, and the whole JSON
# (uspas_llrf/regmap.py, extended by design.py)
SV_SRC  = $(APP_DSP_DIR)/llrf_shell_pkg.sv $(GEN_DIR)/llrf_shell_regmap_pkg.sv
SV_SRC += $(addprefix $(APP_DSP_DIR)/, lb_xdomain.sv lb_rd_mux.sv rx_chain.sv tx_chain.sv diag.sv)
SV_SRC += $(GEN_DIR)/llrf_shell_regs.sv $(SHELL_SRC)

$(GEN_DIR)/%_regmap_pkg.sv $(GEN_DIR)/%_regs.sv $(GEN_DIR)/%.json: $(REGMAP_PY) $(DESIGN_PY)
	$(PYTHON) $(REGMAP_PY) $(addprefix -d ,$(DESIGN_PY)) -o $(GEN_DIR)

$(MODULE).json: $(GEN_DIR)/$(MODULE).json
	cp $< $@

# sv2v converts the SV sources only: it drops comments, and with them the
# verilator lint pragmas of the Verilog library, which is preprocessed as before
$(MODULE)_expand.v: $(SV_SRC) $(LIB_SRC)
	$(SV2V) --version
	$(SV2V) $(SV_SRC) > $@.sv2v
	$(VERILOG) $(VFLAGS_DEP) -E -o $@.lib $(LIB_SRC)
	cat $@.sv2v $@.lib > $@
	rm -f $@.sv2v $@.lib

# boot-time register values: the design directory sets the FSET and the
# register map, whatever DESIGN is in the environment
THIS_DESIGN := $(notdir $(CURDIR))
INIT_REGS_DEP = $(wildcard $(USPAS_LLRF_DIR)/*.py $(USPAS_LLRF_DIR)/model/*.py) $(USPAS_LLRF_DIR)/settings.json $(DESIGN_PY)
$(MODULE)_init_regs.json: $(INIT_REGS_DEP)
	$(PYTHON) $(USPAS_LLRF_DIR)/model/llrf_shell.py -c $(FSET_$(THIS_DESIGN)) -d $(THIS_DESIGN) --write-init-reg $@

# check of basic CDC-correctness
# rewrite the following rule from top_rules.mk to avoid depending directly on the shell source
SHELL_EXTRA_V = $(DSP_DIR)/half_filt.v $(DSP_DIR)/sat_add.v
llrf_shell_yosys.json: $(APP_DSP_DIR)/llrf_shell_skin.v llrf_shell_expand.v $(SHELL_EXTRA_V) $(BUILD_DIR)/cdc_snitch_proc.ys
	$(YOSYS_JSON_PRECHECK)
	$(YOSYS) --version
	$(YOSYS) $(YOSYS_QUIET) -p "read_verilog $(YOSYS_JSON_OPTION) $(filter %.v, $^); script $(filter %_proc.ys, $^); write_json $@"
# exercise with make llrf_shell_expand.v llrf_shell_cdc.txt

CLEAN += llrf_shell_yosys.json llrf_shell_cdc.txt
CLEAN += $(MODULE)_expand.v $(MODULE).json $(MODULE)_init_regs.json cordicg_b22.v
CLEAN_DIRS += $(GEN_DIR)
