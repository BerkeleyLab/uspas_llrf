# Common build rules and variables for LLRF DSP and Design modules
MODULE ?= llrf_shell
LB_AW       = 17    # should be LB_HI
NEWAD_DIRS = .,$(APP_DSP_DIR),$(DSP_DIR)
NEWAD_ARGS = -d $(subst $(SPACE),$(COMMA),$(NEWAD_DIRS)) -i $< -w $(LB_AW) -m
NEWAD_ARGS_llrf_shell = -b69632    # 0x11000

.PHONY: all
all: $(MODULE)_expand.v $(MODULE).json

LLRF_SHELL_SRC ?= $(if $(wildcard llrf_shell.v),llrf_shell.v,$(APP_DSP_DIR)/llrf_shell.v)
APP_DSP_SRC += slow_bridge_shell.v sig_buf.v pulse_gen.v pi_scalar.v ph_acc_general.v ntw_analyzer.v
APP_DSP_SRC += noniq_ddc.v monitor_inlk.v interp_xdomain.v interpolator.v
APP_DSP_SRC += dsp_core.v dds.v ddc.v dac_duc.v cordicg_b22.v cic_waves.v cic_timing.v arc_inlk.v
DSP_SRC += timestamp.v serialize.v serializer_multichannel.v reg_tech_cdc.v reg_delay.v
DSP_SRC += minmax.v fwashout.v freq_gcount.v freq_count.v flag_xdomain.v fiq_interp.v
DSP_SRC += fchan_subset.v dpram.v double_inte_smp.v doublediff.v demand_gpt.v data_xdomain.v
DSP_SRC += cpxmul_fullspeed.v circle_buf.v circle_buf_serial.v cic_wave_recorder.v cic_multichannel.v ccfilt.v
LLRF_SHELL_SRC += $(addprefix $(APP_DSP_DIR)/, $(APP_DSP_SRC))
LLRF_SHELL_SRC += $(addprefix $(DSP_DIR)/, $(DSP_SRC))
LLRF_SHELL_SRC += $(BEDROCK_DIR)/cordic/cstageg.v $(BEDROCK_DIR)/cordic/addsubg.v
LLRF_SHELL_SRC += $(BEDROCK_DIR)/localbus/jit_rad_gateway.v
LLRF_SHELL_SRC += $(SERIAL_IO_DIR)/EVG_EVR/tinyEVR.v $(SERIAL_IO_DIR)/EVG_EVR/timing_core.v $(SERIAL_IO_DIR)/EVG_EVR/evr_ts_cdc.v $(SERIAL_IO_DIR)/EVG_EVR/evrSROC.v

vpath %.v $(APP_DSP_DIR) $(DSP_DIR) $(CORDIC_DIR) $(AUTOGEN_DIR)
VFLAGS_DEP += -I. -I$(APP_DSP_DIR) -y$(APP_DSP_DIR) -y$(DSP_DIR) -y$(CORDIC_DIR) -y$(SERIAL_IO_DIR)/EVG_EVR
VFLAGS_DEP += -I$(AUTOGEN_DIR) -y$(AUTOGEN_DIR) -I$(BEDROCK_DIR)/localbus -y$(BEDROCK_DIR)/localbus
VFLAGS += $(VFLAGS_DEP) -g2012

cordicg_b22.v: $(CORDIC_DIR)/cordicgx.py
	$(PYTHON) $< 22 $@

$(AUTOGEN_DIR)/addr_map_$(MODULE).vh $(AUTOGEN_DIR)/$(MODULE)_auto.vh $(AUTOGEN_DIR)/regmap_$(MODULE).json: $(LLRF_SHELL_SRC)
	mkdir -p $(AUTOGEN_DIR)
	$(PYTHON) $(BUILD_DIR)/newad.py -a $(AUTOGEN_DIR)/addr_map_$(MODULE).vh -o $(AUTOGEN_DIR)/$(MODULE)_auto.vh -l -r $(AUTOGEN_DIR)/regmap_$(MODULE).json $(NEWAD_ARGS) $(NEWAD_ARGS_$(MODULE))

$(AUTOGEN_DIR)/scalar_$(MODULE)_regmap.json: $(LLRF_SHELL_SRC)
	mkdir -p $(AUTOGEN_DIR)
	$(PYTHON) $(BUILD_DIR)/reverse_json.py $< > $@

$(MODULE).json: $(AUTOGEN_DIR)/regmap_$(MODULE).json $(AUTOGEN_DIR)/scalar_$(MODULE)_regmap.json $(wildcard static_regmap.json)
	$(PYTHON) $(BUILD_DIR)/merge_json.py -o $@ -i $^

$(MODULE)_expand.v: $(LLRF_SHELL_SRC) $(AUTOGEN_DIR)/$(MODULE)_auto.vh $(AUTOGEN_DIR)/addr_map_$(MODULE).vh
	$(VERILOG) $(VFLAGS_DEP) -E -o $@ $(LLRF_SHELL_SRC)

$(MODULE)_init_regs.json:
	$(PYTHON) $(USPAS_LLRF_DIR)/model/llrf_shell.py -c $(FSET) --write-init-reg $@

CLEAN += $(MODULE)_expand.v $(MODULE).json cordicg_b22.v
