LLRF_DIR = $(APP_SOC_DIR)/common/llrf
LLRF_AUTO = init_llrf.c llrf_regs_addr.h marble_regs_addr.h

INC_DIR   += -I$(LLRF_DIR)
SRCS      +=  $(LLRF_DIR)/llrf.c init_llrf.c

$(LLRF_DIR)/llrf.o: $(LLRF_AUTO)
ui.o:               $(LLRF_AUTO)
system.o:           $(LLRF_AUTO)

$(APP_DSP_DIR)/llrf_shell.json:
	$(MAKE) -C $(dir $@) $(notdir $@)

$(BSP_DIR)/marble_bsp.json:
	$(MAKE) -C $(dir $@) $(notdir $@)

$(APP_DSP_DIR)/llrf_shell_init_regs.json:
	$(MAKE) -C $(dir $@) $(notdir $@)

llrf_regs_addr.h: $(APP_DSP_DIR)/llrf_shell.json
	$(PYTHON) $(LLRF_DIR)/localbus_address_map.py -i $< -o $@

marble_regs_addr.h: $(BSP_DIR)/marble_bsp.json
	$(PYTHON) $(LLRF_DIR)/localbus_address_map.py -i $< -o $@

init_llrf.c: $(APP_DSP_DIR)/llrf_shell_init_regs.json
	$(PYTHON) $(LLRF_DIR)/gen_init_reg.py -i $< -o $@

CLEAN += $(LLRF_AUTO)
.PHONY: distclean
distclean:: clean
	$(MAKE) -C $(APP_DSP_DIR) clean
	$(MAKE) -C $(BSP_DIR) clean
