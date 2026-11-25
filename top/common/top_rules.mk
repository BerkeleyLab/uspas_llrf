# Board-level build for Marble + Zest, shared by every design.
# A design directory top/<design>/ sets DESIGN and includes this file:
#
#   DESIGN = uspas
#   include ../../dir_list.mk
#   include $(TOP_COMMON_DIR)/top_rules.mk
#
# Override hooks (set or extend them in top/<design>/Makefile before the include):
#   IP_EXPAND  += extra expanded IP sources
#   IP_JSON    += extra register maps merged into the config ROM
#   TOP_SRC    += extra top-level sources (Verilog, netlists)
#   XDC_FILES  += extra constraints, appended to system_top.xdc
#   PIN_MAP     pin map for top.xdc (default: top/common/pin_map.csv)
#   GT_TCL      GT setup TCL sourced by Vivado (default: EVR GTX)
#   SOC_DESIGN  soc/<name>/ used for firmware and SoC settings (default: DESIGN)
# Verilog hooks: design_mid.vh (extra IP and the design's use of board pins),
# design_shell_ports.vh (extra llrf_shell ports) and design_shell_wires.vh
# (declarations of the signals those ports use);
# a copy in top/<design>/ takes precedence over the empty one in top/common/.

include $(TOP)settings.mk

SOC_DESIGN    ?= $(DESIGN)
SOC_BUILD_DIR  = $(SOC_DIR)/$(SOC_DESIGN)/build
# Firmware, system_expand.v and zest_fmc_dp.xdc are built per design in
# soc/<design>/build/ with the shared SoC synth Makefile
SOC_MAKE       = mkdir -p $(SOC_BUILD_DIR) && $(MAKE) -C $(SOC_BUILD_DIR) -f $(abspath $(SOC_COMMON_DIR)/synth/Makefile) DESIGN=$(SOC_DESIGN)

include $(SOC_COMMON_DIR)/common.mk
include $(BUILD_DIR)/top_rules.mk

TARGET   = marble_zest
# Connection to swap-git-ID feature; see comments in that file
GITID_TCL = $(BUILD_DIR)/vivado_tcl/swap_gitid.tcl

GT_TCL  ?= $(BEDROCK_DIR)/serial_io/EVG_EVR/gt_tcl/evr_gtx.tcl
PIN_MAP ?= $(TOP_COMMON_DIR)/pin_map.csv
vpath %.c $(BUILD_DIR)

.PHONY: all system_config system_test system_console_test evr_test console clean topsim topsim_test
all: $(TARGET)_top_$(DESIGN).bit

IP_EXPAND := $(BSP_DIR)/marble_bsp_expand.v $(SOC_BUILD_DIR)/system_expand.v $(DESIGNS_DIR)/$(DESIGN)/llrf_shell_expand.v $(IP_EXPAND)

SUB_IP_DIR = $(BSP_DIR)/ $(DESIGNS_DIR)/$(DESIGN)/

$(BSP_DIR)/marble_bsp_expand.v $(BSP_DIR)/marble_bsp.f: FORCE
	$(MAKE) -C $(dir $@) $(notdir $@)
$(SOC_BUILD_DIR)/system_expand.v $(SOC_BUILD_DIR)/system.f: FORCE
	$(SOC_MAKE) $(notdir $@)
$(DESIGNS_DIR)/$(DESIGN)/llrf_shell_expand.v $(DESIGNS_DIR)/$(DESIGN)/llrf_shell.f: FORCE
	$(MAKE) -C $(dir $@) $(notdir $@)

# Source lists: each block's make writes <block>.f (include directories, then
# its sources, absolute paths, one per line; Verilator -f and iverilog -c read
# it), and the top level merges them without duplicates (the bedrock modules
# the blocks share). The lint and topsim read these lists; Vivado still reads
# the expanded files (plan step 14a).
BLOCK_F := $(BSP_DIR)/marble_bsp.f $(SOC_BUILD_DIR)/system.f $(DESIGNS_DIR)/$(DESIGN)/llrf_shell.f $(BLOCK_F)
# top/<design>/ first: its design hooks take precedence over top/common/'s
MERGE_F  = $(PYTHON) $(TOP_COMMON_DIR)/merge_src_lists.py -o $@ --incdir $(CURDIR) $(TOP_COMMON_DIR) \
	--src $(filter %.v %.sv,$^) -- $(filter %.f,$^)

# the board top (synthesis)
$(TARGET)_top.f: $(TOP_COMMON_DIR)/$(TARGET)_top.v config_romx.v $(SERIAL_IO_DIR)/gmii_to_rgmii.v $(TOP_SRC) $(BLOCK_F) $(TOP_COMMON_DIR)/merge_src_lists.py
	$(MERGE_F)

IP_JSON := $(DESIGNS_DIR)/$(DESIGN)/llrf_shell.json $(BSP_DIR)/marble_bsp.json $(TOP_COMMON_DIR)/marble_zest_top.json $(IP_JSON)

# marble_bsp.json and llrf_shell.json: rules in soc/common/llrf/rules.mk

# Sub-make targets depend on FORCE, so the owning directory's make always
# decides whether they are current (they used to be built only once).
.PHONY: FORCE
FORCE:

# merge_json.py checks that the names are unique; check_lb_map.py checks the
# addresses against the localbus decode of the top (segments, readback,
# overlays). The design's design_mid.vh, else the empty one in top/common/.
DESIGN_MID_VH = $(firstword $(wildcard design_mid.vh) $(TOP_COMMON_DIR)/design_mid.vh)
# (the check needs only the names of the defines)
DEFINE_NAMES  = $(sort $(foreach d,$(filter -D%,$(SYNTH_OPT)),$(firstword $(subst =, ,$(d:-D%=%)))))
$(TARGET).json: $(IP_JSON) $(TOP_COMMON_DIR)/check_lb_map.py $(TOP_COMMON_DIR)/marble_zest_mid.vh $(DESIGN_MID_VH)
	$(PYTHON) $(BUILD_DIR)/merge_json.py -o $@.tmp -i $(IP_JSON)
	$(PYTHON) $(TOP_COMMON_DIR)/check_lb_map.py -m $@.tmp -j $(IP_JSON) \
		-v $(TOP_COMMON_DIR)/marble_zest_mid.vh $(DESIGN_MID_VH) $(addprefix -D ,$(DEFINE_NAMES))
	mv $@.tmp $@

config_romx.v: $(TARGET).json
	$(PYTHON) -m leep.build_rom -v $@ --placeholder_rev -j $< -d "$(DESIGN)"

# Used mostly to verify gitid reported by the LEEP Ethernet
GIT_ID = $(shell git rev-parse --verify HEAD)
GIT_32BIT_ID = $(shell git rev-parse --short=8 --verify HEAD)
SYNTH_OPT += -DGIT_32BIT_ID=32'h$(GIT_32BIT_ID)

$(SOC_BUILD_DIR)/system32.dat: FORCE
	$(SOC_MAKE) system32.dat

$(SOC_BUILD_DIR)/zest_fmc_dp.xdc: FORCE
	$(SOC_MAKE) zest_fmc_dp.xdc

top.xdc: $(BOARD_SUPPORT_DIR)/marble/Marble.xdc $(PIN_MAP)
	$(PYTHON) $(BADGER_DIR)/tests/meta-xdc.py $^ > $@

system_top.xdc: $(TOP_COMMON_DIR)/timing.xdc $(SOC_BUILD_DIR)/zest_fmc_dp.xdc top.xdc $(XDC_FILES)
	cat $^ > $@

# Construct an overall (configuration-dependent) .d file.
$(TARGET)_top.d: $(TOP_COMMON_DIR)/$(TARGET)_top.v config_romx.v $(BEDROCK_DIR)/serial_io/gmii_to_rgmii.v $(IP_EXPAND) $(TOP_SRC) system_top.xdc $(SOC_BUILD_DIR)/system32.dat
	echo $^ | tr ' ' '\n' > $@

#: Build bitstream
$(TARGET)_top_$(DESIGN).bit: $(TOP_COMMON_DIR)/$(TARGET)_top.tcl $(GT_TCL) $(GITID_TCL) $(TARGET)_top.d bit_stamp_mod
	$(VIVADO_CMD) -source $< -tclargs $(TARGET)_top.d $(DESIGN) "$(SYNTH_OPT)" $(GITID_TCL) $(GT_TCL)

IP_ADDRESS = 192.168.19.$(MARBLE_SERIAL)

BITSTREAM = $(TARGET)_top_$(DESIGN).$(GIT_32BIT_ID).bit
system_config:
	@echo "Using Marble with serial number $(MARBLE_SERIAL)"
	openocd \
	-c "adapter serial $(MARBLE_SN);" \
	-f $(TOP_COMMON_DIR)/marble.cfg \
	-c "init; xc7_program xc7.tap; pld load 0 $(BITSTREAM); exit"

# check Ethernet and system selftest status
#: SoC console on the Marble's USB UART (see soc/common/synth/Makefile)
console:
	$(SOC_MAKE) console

system_test:
	ping -v -c 4 -w 20 $(IP_ADDRESS)
	test "$$(leep leep://$(IP_ADDRESS):803 gitid)" = "$(GIT_ID)" && echo "gitid OK" && \
	leep leep://$(IP_ADDRESS):803 reg system_bist_pass | awk ' $$2!=00000001 { exit 1 }'

#: post-boot firmware check: the console must answer '?' with this commit's
#: GIT_REV_ID (needs a UART0 interrupt and the main loop running)
#: override where udev links are missing, e.g. in a CI container
CONSOLE_PORT ?= /dev/serial/by-id/usb-LBNL_Marble_$(MARBLE_SN)-if02-port0
system_console_test:
	$(PYTHON) -m uspas_llrf.tools.marble_console $(CONSOLE_PORT) --git-id $(GIT_32BIT_ID)

#: lint of the board top with Verilator: the connections between the blocks
#: (widths, missing ports, multiple drivers). The warnings inside the blocks
#: are waived here; each block is linted in its own directory (make lint in
#: designs/<design>/). The Xilinx primitives are the port-only black boxes of
#: Yosys's cell library (Vivado's unisim models do not elaborate in Verilator).
LINT_VERILATOR ?= verilator  # not $(VERILATOR): bedrock sets it to -Wall -Wno-fatal
YOSYS_XILINX   ?= $(abspath $(dir $(shell which yosys))../share/yosys/xilinx)
# the primitives, and the ports of the GT IP that Vivado generates
LINT_LIB        = $(CURDIR)/xilinx_lint_cells.v $(YOSYS_XILINX)/cells_sim.v $(abspath $(TOP_COMMON_DIR)/$(TARGET)_top_lint_stubs.v)
# GIT_32BIT_ID: its quote would need shell quoting; the lint uses the default
LINT_DEFS       = $(filter-out -DGIT_32BIT_ID=%,$(SYNTH_OPT))
# blocks the lint reads by their ports only (header up to the port list's
# closing ");"): zest.v, whose array of reg_tech_cdc instances writing an
# unpacked array Verilator does not support
LINT_PORTS_ONLY = $(abspath $(BOARD_SUPPORT_DIR)/zest_soc/zest.v)
.PHONY: lint
lint: $(TARGET)_top_lint.f $(TARGET)_top_lint.vlt xilinx_lint_cells.v ports_only.v
	$(LINT_VERILATOR) --lint-only -Wno-TIMESCALEMOD --top-module $(TARGET)_top $(LINT_DEFS) \
		$(TARGET)_top_lint.vlt -f $(TARGET)_top_lint.f $(CURDIR)/ports_only.v $(addprefix -v ,$(LINT_LIB))

$(TARGET)_top_lint.f: $(TARGET)_top.f
	grep -vxF $(addprefix -e ,$(LINT_PORTS_ONLY)) $< > $@
ports_only.v: $(LINT_PORTS_ONLY) $(TOP_COMMON_DIR)/top_rules.mk
	for f in $(LINT_PORTS_ONLY); do echo "// ports of $$f"; awk '/^module /,/^\);/' $$f; echo endmodule; done > $@

xilinx_lint_cells.v: $(YOSYS_XILINX)/cells_xtra.v $(TOP_COMMON_DIR)/xilinx_lint_cells.py
	$(PYTHON) $(TOP_COMMON_DIR)/xilinx_lint_cells.py $< -o $@

# waivers: every block source, the primitive library and the port-only blocks
$(TARGET)_top_lint.vlt: $(BLOCK_F) $(TOP_COMMON_DIR)/top_rules.mk
	{ echo '`verilator_config'; \
	  grep -hv '^+' $(BLOCK_F) | sort -u | sed 's/.*/lint_off -file "&"/'; \
	  for f in $(LINT_LIB) $(CURDIR)/ports_only.v; do \
	    for r in "" "-rule SPECIFYIGN "; do echo "lint_off $$r-file \"$$f\""; done; done; } > $@

# ===== topsim: Verilator simulation of the top
# marble_zest_frame.v is the top without the Zest and the Xilinx I/O (it
# includes the same marble_zest_mid.vh); topsim.cpp drives the clocks, the
# UART (printed) and Ethernet through badger's ethernet_model.c. With
# TOPSIM_NET=udp (default) udp_tap.c bridges a localhost UDP port to it
# (leep://127.0.0.1:$$TOPSIM_UDP_PORT, default 8030), with TOPSIM_NET=tap a tap
# device (badger/tests/tap-setup.sh; ping 192.168.7.123).
# TOPSIM_TRACE=1 builds with FST tracing (+trace at run time); off by default:
# with it, Verilator 5.052 runs out of memory (over 75 GB) on this design.
TOPSIM_NET  ?= udp
TOPSIM_TRACE ?=
TOPSIM_DEFS  = -DSIMULATE $(sort $(LINT_DEFS))
ETH_TESTS    = $(BADGER_DIR)/tests
TOPSIM_C     = $(TOP_COMMON_DIR)/topsim.cpp $(ETH_TESTS)/ethernet_model.c $(ETH_TESTS)/crc32.c
TOPSIM_C    += $(if $(filter tap,$(TOPSIM_NET)),$(ETH_TESTS)/tap_alloc.c,$(TOP_COMMON_DIR)/udp_tap.c)
# the frame, its UART and the XADC model (topsim_models.v), then the blocks
topsim.f: $(TOP_COMMON_DIR)/marble_zest_frame.v config_romx.v $(SERIAL_IO_DIR)/simpleuart.v $(TOP_COMMON_DIR)/topsim_models.v $(BLOCK_F) $(TOP_COMMON_DIR)/merge_src_lists.py
	$(MERGE_F)
# the lint waivers, and the frame's UART (bedrock)
topsim.vlt: $(TARGET)_top_lint.vlt
	{ cat $<; echo 'lint_off -file "$(abspath $(SERIAL_IO_DIR)/simpleuart.v)"'; } > $@
# The SoC's memory image, topsim32.dat (marble_zest_frame.v), read when the
# simulation starts ($$readmemh), so a new one needs no rebuild; named apart
# from the bitstream's system32.dat, which Vivado finds by name.
# TOPSIM_FW=sim (default): the firmware's SIMULATION build
# (soc/common/synth/Makefile TOPSIM=1, in its own directory), which reads the
# XADC, initializes the shell and writes system_bist_pass within seconds.
# TOPSIM_FW=full: the bitstream's firmware, whose Marble and Zest init wait
# for devices topsim does not model (over half an hour).
TOPSIM_FW     ?= sim
TOPSIM_SOC_DIR = $(SOC_DIR)/$(SOC_DESIGN)/build_topsim
$(TOPSIM_SOC_DIR)/system32.dat: FORCE
	mkdir -p $(TOPSIM_SOC_DIR) && $(MAKE) -C $(TOPSIM_SOC_DIR) -f $(abspath $(SOC_COMMON_DIR)/synth/Makefile) DESIGN=$(SOC_DESIGN) TOPSIM=1 system32.dat
topsim32.dat: $(if $(filter full,$(TOPSIM_FW)),$(SOC_BUILD_DIR),$(TOPSIM_SOC_DIR))/system32.dat FORCE
	cmp -s $< $@ || cp $< $@
Vmarble_zest_frame: topsim.f topsim.vlt $(TOPSIM_C) FORCE
	$(LINT_VERILATOR) --cc --exe --build -j 0 $(if $(TOPSIM_TRACE),--trace-fst) --timing -O3 -Wno-fatal -Wno-TIMESCALEMOD \
		--top-module marble_zest_frame $(TOPSIM_DEFS) -CFLAGS "-I$(ETH_TESTS) -Wno-logical-op" -LDFLAGS -pthread \
		topsim.vlt -f topsim.f $(abspath $(TOPSIM_C))
	cp obj_dir/$@ $@

#: build the Verilator simulation of the top (Vmarble_zest_frame; run it
#: from this directory; with TOPSIM_TRACE=1, +trace writes topsim.vcd)
topsim: Vmarble_zest_frame topsim32.dat

# cdc_snitch over the whole simulated top (make topsim_cdc.txt; bedrock's
# %_cdc.txt rule), so it sees the crossings between blocks as well as inside
# them. Yosys reads the Verilog sources of topsim.f; sv2v converts its SV
# sources first, as for the shell's own check (designs/rules.mk). The
# synthesis defines (no SIMULATE: Yosys does not read the simulation code).
# zest.v (LINT_PORTS_ONLY) is not in the frame, and Yosys cannot parse it.
# -defer and an explicit top: elaborate only the frame's tree, with the
# parameters it uses (the defaults of evr_wrapper, not in the frame, would
# need the GT IP); the hierarchy check still wants half_filt and sat_add in
# generate branches not taken (as SHELL_EXTRA_V in designs/rules.mk).
SV2V    ?= sv2v
CDC_DEFS = $(sort $(LINT_DEFS))
CDC_EXTRA_V = $(addprefix $(BEDROCK_DIR)/dsp/, half_filt.v sat_add.v)
topsim_sv2v.v: topsim.f
	$(SV2V) $(CDC_DEFS) $$(grep '\.sv$$' $<) > $@
# Yosys also elaborates memory_pack with its default image, system32.hex
system32.hex: topsim32.dat
	cp $< $@
topsim_yosys.json: topsim.f topsim_sv2v.v system32.hex $(CDC_EXTRA_V) $(BUILD_DIR)/cdc_snitch_proc.ys
	$(YOSYS) --version
	$(YOSYS) $(YOSYS_QUIET) -p "read_verilog -defer $(YOSYS_JSON_OPTION) $(CDC_DEFS) $$(sed -n 's/^+incdir+/-I/p' $< | tr '\n' ' ') \
		topsim_sv2v.v $$(grep '\.v$$' $< | grep -vxF $(LINT_PORTS_ONLY) | tr '\n' ' ') $(CDC_EXTRA_V); \
		hierarchy -top marble_zest_frame; script $(BUILD_DIR)/cdc_snitch_proc.ys; write_json $@"

#: boot the simulated top and check it over LEEP (topsim_test.py)
topsim_test: topsim $(TARGET).json
	$(PYTHON) $(TOP_COMMON_DIR)/topsim_test.py -m $(TARGET).json -j $(IP_JSON) \
		--init-regs $(DESIGNS_DIR)/$(DESIGN)/llrf_shell_init_regs.json

CLEAN += system_top.xdc top.xdc *.bin *.bit $(IP_BIT_D)
CLEAN += config_romx.v $(TARGET).json Vmarble_zest_frame system32.dat topsim32.dat system32.hex
CLEAN += $(TARGET)_top.prm bit_stamp_mod $(TARGET)_top.d *.log *.jou
CLEAN += $(TARGET)_top.f $(TARGET)_top_lint.f $(TARGET)_top_lint.vlt xilinx_lint_cells.v ports_only.v topsim.f topsim.vlt
CLEAN += topsim_cdc.txt topsim_yosys.json topsim_sv2v.v topsim_console.log
CLEAN_DIRS += .Xil _xilinx obj_dir bit_stamp_mod.dSYM $(SOC_BUILD_DIR) $(TOPSIM_SOC_DIR)

include $(BUILD_DIR)/bottom_rules.mk
clean::
	@for d in $(SUB_IP_DIR); do \
	    $(MAKE) -C $$d clean; \
	done;
