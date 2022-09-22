BUILD_DIR=../build/berkeleylab_marble

-include $(BUILD_DIR)/software/include/generated/variables.mak
-include $(SOC_DIRECTORY)/software/common.mak

SRCS = main.c

OBJECTS  = crt0.o $(SRCS:.c=.o)
LSCRIPT = linker.ld

all: firmware.bin

# pull in dependency info for *existing* .o files
-include $(OBJECTS:.o=.d)

# same as in bios/Makefile
%.bin: %.elf
	$(OBJCOPY) -O binary $< $@
ifneq ($(OS),Windows_NT)
	chmod -x $@
endif
ifeq ($(CPUENDIANNESS),little)
	@$(PYTHON) -m litex.soc.software.mkmscimg $@ --little
else
	@$(PYTHON) -m litex.soc.software.mkmscimg $@
endif

CFLAGS += 	-Wmissing-field-initializers \
			-Wclobbered \
			-Wempty-body \
			-Wignored-qualifiers \
			-Woverride-init \
			-Wtype-limits \
			-Wuninitialized \
			-MMD -MP \
			# -Wsign-compare
LDFLAGS += -Wl,--print-memory-usage,--strip-debug
firmware.elf: $(OBJECTS) $(LSCRIPT)
	$(CC) $(LDFLAGS) -T $(LSCRIPT) -N -o $@ \
		$(OBJECTS) \
		$(PACKAGES:%=-L$(BUILD_DIR)/software/%) \
		-Wl,--whole-archive \
		-Wl,--gc-sections,-Bstatic \
		-Wl,-Map,$@.map \
		$(LIBS:lib%=-l%)
ifneq ($(OS),Windows_NT)
	chmod -x $@
endif

VPATH = $(BIOS_DIRECTORY):$(BIOS_DIRECTORY)/cmds:$(CPU_DIRECTORY)

%.o: %.c
	$(compile)

%.o: %.S
	$(assemble)

%.lst: %.elf
	$(TRIPLE)-objdump -d $< > $@

clean:
	$(RM) $(OBJECTS) $(OBJECTS:.o=.d) firmware.elf.map firmware.elf firmware.bin

.PHONY: all clean load
