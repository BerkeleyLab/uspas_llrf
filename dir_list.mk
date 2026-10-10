TOP := $(dir $(lastword $(MAKEFILE_LIST)))
SUBMODULES_DIR     = $(TOP)submodules
BEDROCK_DIR        = $(SUBMODULES_DIR)/bedrock
SOC_DIR            = $(TOP)soc
SOC_COMMON_DIR     = $(SOC_DIR)/common
TOP_COMMON_DIR     = $(TOP)top/common
BSP_DIR            = $(TOP)marble_bsp
APP_DSP_DIR        = $(TOP)llrf_dsp
DESIGNS_DIR        = $(TOP)designs
USPAS_LLRF_DIR     = $(TOP)uspas_llrf
MB_MOCKUP_DIR      = $(SUBMODULES_DIR)/modbus_mockup

include $(BEDROCK_DIR)/dir_list.mk
