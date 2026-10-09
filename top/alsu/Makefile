# Marble + Zest top level for the alsu design; rules in top/common/top_rules.mk
DESIGN = alsu
include ../../dir_list.mk
# ALSU board IO in design_mid.vh: PMOD1 ARC detectors, PMOD2 FO board, and the
# Modbus UART on the SoC expansion port
SYNTH_OPT += -DDESIGN_OWNS_PMOD1 -DDESIGN_OWNS_PMOD2 -DDESIGN_OWNS_PERMITS -DDESIGN_SOC_EXPANSION
include $(TOP_COMMON_DIR)/top_rules.mk
