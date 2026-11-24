LLRF_DIR = $(SOC_COMMON_DIR)/llrf
LLRF_AUTO = init_llrf.c llrf_regs_addr.h marble_regs_addr.h

INC_DIR   += -I$(LLRF_DIR)
# llrf.c by name and vpath: it includes the design's llrf_regs_addr.h, so its
# object is built in each build directory, not next to the shared source
SRCS      +=  llrf.c init_llrf.c
vpath %.c $(LLRF_DIR)

DESIGN        ?= uspas
DESIGN_DSP_DIR = $(DESIGNS_DIR)/$(DESIGN)

llrf.o:             $(LLRF_AUTO)
ui.o:               $(LLRF_AUTO)
system.o:           $(LLRF_AUTO)

$(DESIGN_DSP_DIR)/llrf_shell.json: FORCE
	$(MAKE) -C $(dir $@) $(notdir $@)

$(BSP_DIR)/marble_bsp.json: FORCE
	$(MAKE) -C $(dir $@) $(notdir $@)

$(DESIGN_DSP_DIR)/llrf_shell_init_regs.json: FORCE
	$(MAKE) -C $(dir $@) $(notdir $@)

# Sub-make targets depend on FORCE, so the owning directory's make always
# decides whether they are current (they used to be built only once).
.PHONY: FORCE
FORCE:

llrf_regs_addr.h: $(DESIGN_DSP_DIR)/llrf_shell.json $(LLRF_DIR)/localbus_address_map.py
	$(PYTHON) $(LLRF_DIR)/localbus_address_map.py -i $< -o $@

marble_regs_addr.h: $(BSP_DIR)/marble_bsp.json $(LLRF_DIR)/localbus_address_map.py
	$(PYTHON) $(LLRF_DIR)/localbus_address_map.py -i $< -o $@

init_llrf.c: $(DESIGN_DSP_DIR)/llrf_shell_init_regs.json
	$(PYTHON) $(LLRF_DIR)/gen_init_reg.py -i $< -o $@

CLEAN += $(LLRF_AUTO)
.PHONY: distclean
distclean:: clean
	$(MAKE) -C $(DESIGN_DSP_DIR) clean
	$(MAKE) -C $(BSP_DIR) clean
