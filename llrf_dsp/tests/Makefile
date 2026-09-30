TARGETS := all clean
SUBDIRS := ddc dds duc pulse_gen llrf_dsp cic_waves

$(TARGETS): $(SUBDIRS)
$(SUBDIRS):
	$(MAKE) -C $@ $(MAKECMDGOALS)

.PHONY: $(TARGETS) $(SUBDIRS)