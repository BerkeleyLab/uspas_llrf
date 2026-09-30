include ../dir_list.mk
include $(TOP)settings.mk
include $(BUILD_DIR)/top_rules.mk
all:
	$(MAKE) -C tests FSET=$(FSET)

clean::
	$(MAKE) -C tests clean
include $(BUILD_DIR)/bottom_rules.mk
