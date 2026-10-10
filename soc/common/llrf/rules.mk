LLRF_DIR = $(SOC_COMMON_DIR)/llrf
LLRF_AUTO = init_llrf.c llrf_regs_addr.h marble_regs_addr.h

INC_DIR   += -I$(LLRF_DIR)
SRCS      +=  $(LLRF_DIR)/llrf.c init_llrf.c

DESIGN        ?= uspas
DESIGN_DSP_DIR = $(DESIGNS_DIR)/$(DESIGN)

$(LLRF_DIR)/llrf.o: $(LLRF_AUTO)
ui.o:               $(LLRF_AUTO)
system.o:           $(LLRF_AUTO)

$(DESIGN_DSP_DIR)/llrf_shell.json:
	$(MAKE) -C $(dir $@) $(notdir $@)

$(BSP_DIR)/marble_bsp.json:
	$(MAKE) -C $(dir $@) $(notdir $@)

$(DESIGN_DSP_DIR)/llrf_shell_init_regs.json:
	$(MAKE) -C $(dir $@) $(notdir $@)

llrf_regs_addr.h: $(DESIGN_DSP_DIR)/llrf_shell.json
	$(PYTHON) $(COMMON_DIR)/localBusAddressMap.py $< $@

marble_regs_addr.h: $(BSP_DIR)/marble_bsp.json
	$(PYTHON) $(LLRF_DIR)/localbus_address_map.py -i $< -o $@

init_llrf.c: $(DESIGN_DSP_DIR)/llrf_shell_init_regs.json
	$(PYTHON) $(LLRF_DIR)/gen_init_reg.py -i $< -o $@

CLEAN += $(LLRF_AUTO)
.PHONY: distclean
distclean:: clean
	$(MAKE) -C $(DESIGN_DSP_DIR) clean
	$(MAKE) -C $(BSP_DIR) clean
