# Forwarder kept for one release: the top level is now built per design in
# top/<design>/ (see top/common/top_rules.mk). `make DESIGN=x <goal>` here runs
# `make -C ../x <goal>`.
DESIGN ?= uspas

.PHONY: all $(MAKECMDGOALS)
all $(MAKECMDGOALS):
	@echo "top/marble_zest is deprecated; use make -C top/$(DESIGN)"
	$(MAKE) -C ../$(DESIGN) $@
