MODULE    = marble_bsp

RTEFI_CLIENT_LIST = hello.v speed_test.v lb_gateway.v spi_flash.v
include $(BADGER_DIR)/rules.mk

# =====
# Sources, listed explicitly
# badger's packet engine: rtefi_center and its clients, and the modules the
# clients instantiate (spi_flash_engine, mem_gateway, tests/spi_gate)
BADGER_V  = rtefi_center.v scanner.v pbuf_writer.v udp_port_cam.v crc8e_guts.v construct.v
BADGER_V += ones_chksum.v xformer.v ethernet_crc_add.v hack_icmp_cksum.v mac_subset.v precog.v test_tx_mac.v
BADGER_V += hello.v speed_test.v lb_gateway.v spi_flash.v spi_flash_engine.v mem_gateway.v
BADGER_V  := $(addprefix $(BADGER_DIR)/, $(BADGER_V)) $(BADGER_DIR)/tests/spi_gate.v
# generated here (badger/rules.mk): rtefi_blob.v with the clients, construct_tx_table.v
GEN_V     = rtefi_blob.v construct_tx_table.v
# EVR GT wrapper, and the MMC mailbox with its memory
BOARD_V   = $(SERIAL_IO_DIR)/EVG_EVR/evr_gt_wrapper.v $(PROJECTS_DIR)/test_marble_family/mmc_mailbox.v $(HOMELESS_DIR)/fake_dpram.v
# bedrock DSP modules, some shared with the DSP shell and the SoC (the top
# level's merged source list keeps one copy)
DSP_V     = dpram.v data_xdomain.v flag_xdomain.v freq_count.v freq_gcount.v phase_diff.v phaset.v reg_delay.v reg_tech_cdc.v
DSP_V    := $(addprefix $(DSP_DIR)/, $(DSP_V))
# only for simulation (spi_flash's SPI engine)
SIM_V     = $(PICORV_DIR)/gateware/spi_engine.v

BSP_SRC   = $(MODULE).v $(GEN_DIR)/$(MODULE)_regs.v $(GEN_V) $(BOARD_V) $(BADGER_V) $(DSP_V)

# Registers, status words and windows: uspas_llrf/regmap.py --bsp writes the
# register file (plain Verilog) and the JSON
GEN_DIR    = _gen
REGMAP_PY  = $(USPAS_LLRF_DIR)/regmap.py
$(GEN_DIR)/%_regs.v $(GEN_DIR)/%.json: $(REGMAP_PY)
	$(PYTHON) $(REGMAP_PY) --bsp -o $(GEN_DIR)

$(GEN_DIR)/regmap_%.vh: %.json
	mkdir -p $(GEN_DIR); \
	$(PYTHON) $(BEDROCK_DIR)/localbus/gen_regmap.py -i $< -o $@

$(MODULE).json: $(GEN_DIR)/$(MODULE).json
	cp $< $@

# source list for the top level (top/common/top_rules.mk; Vivado, lint and
# topsim read it): include directories, then every source the BSP needs, SIM_V
# included (the top level merges the lists and drops the files the blocks
# share), absolute paths
$(MODULE).f: $(BSP_SRC) $(SIM_V)
	printf '%s\n' $(addprefix +incdir+,$(abspath $(patsubst -I%,%,$(filter -I%,$(VFLAGS_DEP))) $(GEN_DIR))) $(abspath $^) > $@

# the testbench compiles everything, with the sources named: a module missing
# from the lists is an error at elaboration
# register names for the testbench (regmap_$(MODULE).vh), from the generated JSON
VFLAGS += -I$(GEN_DIR)
$(TEST_BENCH): $(BSP_SRC) $(SIM_V) $(GEN_DIR)/regmap_$(MODULE).vh

CLEAN += $(MODULE).json $(MODULE)_init_regs.json
CLEAN_DIRS += $(GEN_DIR)
CLEAN += $(MODULE).f
