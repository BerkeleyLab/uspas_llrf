# Marble + Zest top level for the lemp design; rules in top/common/top_rules.mk
DESIGN = lemp
include ../../dir_list.mk
# LEMP board IO in design_mid.vh: PMOD1 rear I/O board, PMOD2 trigger and
# event diagnostics, ZEST_PMOD1 SSSB, the HDMI LVDS trigger outputs, and
# interlock_wrapper on localbus segment 2
SYNTH_OPT += -DDESIGN_OWNS_PMOD1 -DDESIGN_OWNS_PMOD2 -DDESIGN_OWNS_ZEST_PMOD1 -DDESIGN_OWNS_ZEST_PMOD2
SYNTH_OPT += -DDESIGN_LB_SEG2
INTLK_DIR  = $(DESIGNS_DIR)/lemp/interlock
IP_EXPAND += $(INTLK_DIR)/interlock_wrapper_expand.v
IP_JSON   += $(INTLK_DIR)/interlock_wrapper.json
XDC_FILES += design.xdc
include $(TOP_COMMON_DIR)/top_rules.mk

$(INTLK_DIR)/interlock_wrapper_expand.v $(INTLK_DIR)/interlock_wrapper.json: FORCE
	$(MAKE) -C $(dir $@) $(notdir $@)
