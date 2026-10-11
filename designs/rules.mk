# Common build rules and variables for LLRF DSP and Design modules
MODULE     = llrf_shell
GEN_DIR    = _gen
REGMAP_PY  = $(USPAS_LLRF_DIR)/regmap.py
DESIGN_PY  = $(wildcard design.py)

.PHONY: all
all: $(MODULE)_expand.v $(MODULE).json

LLRF_SHELL_SRC = llrf_shell.v
APP_DSP_SRC += slow_bridge_shell.v sig_buf.v pulse_gen.v pi_scalar.v ph_acc_general.v ntw_analyzer.v
APP_DSP_SRC += noniq_ddc.v monitor_inlk.v interp_xdomain.v interpolator.v
APP_DSP_SRC += dsp_core.v dds.v ddc.v dac_duc.v cic_waves.v cic_timing.v arc_inlk.v
DSP_SRC     += timestamp.v serialize.v serializer_multichannel.v reg_tech_cdc.v reg_delay.v
DSP_SRC     += minmax.v fwashout.v freq_gcount.v freq_count.v flag_xdomain.v fiq_interp.v
DSP_SRC     += fchan_subset.v dpram.v double_inte_smp.v doublediff.v demand_gpt.v data_xdomain.v
DSP_SRC     += cpxmul_fullspeed.v circle_buf.v circle_buf_serial.v cic_wave_recorder.v cic_multichannel.v ccfilt.v
EVR_SRC     += tinyEVR.v timing_core.v evr_ts_cdc.v evrSROC.v
LLRF_SHELL_SRC += $(addprefix $(APP_DSP_DIR)/, $(APP_DSP_SRC))
LLRF_SHELL_SRC += $(addprefix $(DSP_DIR)/, $(DSP_SRC))
LLRF_SHELL_SRC += $(addprefix $(SERIAL_IO_DIR)/EVG_EVR/, $(EVR_SRC))
LLRF_SHELL_SRC += $(BEDROCK_DIR)/cordic/cstageg.v $(BEDROCK_DIR)/cordic/addsubg.v
LLRF_SHELL_SRC += $(BEDROCK_DIR)/localbus/jit_rad_gateway.v
LLRF_SHELL_SRC += cordicg_b22.v

VFLAGS_DEP += -I$(GEN_DIR)
VFLAGS += -g2012

cordicg_b22.v:
	$(PYTHON) $(CORDIC_DIR)/cordicgx.py 22 $@

# register storage, decode and mirror, and the register part of the JSON
# (uspas_llrf/regmap.py, extended by design.py)
$(GEN_DIR)/%_regs.vh $(GEN_DIR)/regmap_%.json: $(REGMAP_PY) $(DESIGN_PY)
	$(PYTHON) $(REGMAP_PY) $(addprefix -d ,$(DESIGN_PY)) -o $(GEN_DIR)

# status registers, from the "// alias:" comments of the readback mux
$(GEN_DIR)/scalar_%_regmap.json: %.v
	mkdir -p $(GEN_DIR); $(PYTHON) $(BUILD_DIR)/reverse_json.py $< > $@

$(MODULE).json: $(GEN_DIR)/regmap_$(MODULE).json $(GEN_DIR)/scalar_$(MODULE)_regmap.json $(wildcard static_regmap.json)
	$(PYTHON) $(BUILD_DIR)/merge_json.py -o $@ -i $^

$(MODULE)_expand.v: $(LLRF_SHELL_SRC) $(GEN_DIR)/$(MODULE)_regs.vh
	$(VERILOG) $(VFLAGS_DEP) -E -o $@ $(LLRF_SHELL_SRC)

$(MODULE)_init_regs.json:
	$(PYTHON) $(USPAS_LLRF_DIR)/model/llrf_shell.py -c $(FSET) --write-init-reg $@

# check of basic CDC-correctness
# rewrite the following rule from top_rules.mk to avoid depending directly on llrf_shell.v (%.v)
SHELL_EXTRA_V = $(DSP_DIR)/half_filt.v $(DSP_DIR)/sat_add.v
llrf_shell_yosys.json: $(APP_DSP_DIR)/llrf_shell_skin.v llrf_shell_expand.v $(SHELL_EXTRA_V) $(BUILD_DIR)/cdc_snitch_proc.ys
	$(YOSYS_JSON_PRECHECK)
	$(YOSYS) --version
	$(YOSYS) $(YOSYS_QUIET) -p "read_verilog $(YOSYS_JSON_OPTION) $(filter %.v, $^); script $(filter %_proc.ys, $^); write_json $@"
# exercise with make llrf_shell_expand.v llrf_shell_cdc.txt

CLEAN += llrf_shell_yosys.json llrf_shell_cdc.txt
CLEAN += $(MODULE)_expand.v $(MODULE).json cordicg_b22.v
CLEAN_DIRS += $(GEN_DIR)
