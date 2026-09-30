TOP := $(dir $(lastword $(MAKEFILE_LIST)))
SUBMODULES_DIR     = $(TOP)submodules
BEDROCK_DIR        = $(SUBMODULES_DIR)/bedrock
APP_SOC_DIR        = $(TOP)soc/marble_zest
BSP_DIR            = $(TOP)marble_bsp
APP_DSP_DIR        = $(TOP)llrf_dsp
DESIGNS_DIR        = $(TOP)designs
USPAS_LLRF_DIR     = $(TOP)uspas_llrf

include $(BEDROCK_DIR)/dir_list.mk
