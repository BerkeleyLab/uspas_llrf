LLRF_DIR = $(APP_SOC_DIR)/common/llrf
LLRF_AUTO = init_llrf.c llrf_regs_addr.h

INC_DIR   += -I$(LLRF_DIR)
SRCS      +=  $(LLRF_DIR)/llrf.c init_llrf.c

$(LLRF_DIR)/llrf.o: $(LLRF_AUTO)
ui.o:               $(LLRF_AUTO)
system.o:           $(LLRF_AUTO)

$(APP_DSP_DIR)/llrf_shell.json:
	$(MAKE) -C $(dir $@) $(notdir $@)

$(APP_DSP_DIR)/llrf_shell_init_regs.json:
	$(MAKE) -C $(dir $@) $(notdir $@)

llrf_regs_addr.h: $(APP_DSP_DIR)/llrf_shell.json
	python3 $(COMMON_DIR)/localBusAddressMap.py $< $@

init_llrf.c: $(APP_DSP_DIR)/llrf_shell_init_regs.json
	python3 $(LLRF_DIR)/gen_init_reg.py -i $< -o $@

CLEAN += llrf_regs_addr.h init_llrf.c
.PHONY: distclean
distclean:: clean
	$(MAKE) -C $(APP_DSP_DIR) clean
