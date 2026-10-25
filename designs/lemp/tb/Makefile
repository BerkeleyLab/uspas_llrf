# LEMP block unit tests (the llrf_shell TB runs separately, in CI llrf_shell_test)
TARGETS := all clean
SUBDIRS := fiducial_int_gen triggers

$(TARGETS): $(SUBDIRS)
$(SUBDIRS):
	$(MAKE) -C $@ $(MAKECMDGOALS)

.PHONY: $(TARGETS) $(SUBDIRS)
