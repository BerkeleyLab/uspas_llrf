TOP := $(dir $(lastword $(MAKEFILE_LIST)))
SUBMODULES_DIR     = $(TOP)submodules
BEDROCK_DIR        = $(SUBMODULES_DIR)/bedrock
APP_SOC_DIR        = $(TOP)soc/marble_zest
APP_SOC_SYN_DIR    = $(TOP)soc/marble_zest/synth
BSP_DIR            = $(TOP)marble_bsp
APP_DSP_DIR        = $(TOP)llrf_dsp
# MARBLE_DIR         = $(BOARD_SUPPORT_DIR)/marble_soc
MARBLE_DIR         = $(APP_SOC_DIR)/marble_soc
ZEST_DIR           = $(BOARD_SUPPORT_DIR)/zest_soc
HARDWARE            = marble

include $(BEDROCK_DIR)/dir_list.mk
