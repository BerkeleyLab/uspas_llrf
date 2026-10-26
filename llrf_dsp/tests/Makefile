TARGETS := all clean
SUBDIRS := ddc dds duc pulse_gen loop_ctrl rx_chain llrf_dsp cic_waves

$(TARGETS): $(SUBDIRS)
$(SUBDIRS):
	$(MAKE) -C $@ $(MAKECMDGOALS)

.PHONY: $(TARGETS) $(SUBDIRS)