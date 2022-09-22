.PHONY: all load clean flash boot

PLATFORM = berkeleylab_marble
TOP_SRC = marble.py
BIOS_FILE = build/$(PLATFORM)/software/bios/bios.bin
GATEWARE = build/$(PLATFORM)/gateware/$(PLATFORM).bit
FIRMWARE = firmware/firmware.bin

ARGS = --with-etherbone \
		--csr-csv build/csr.csv
ARGS += --with-bist
ARGS += --spd-dump targets/sdram_spd.txt

all: $(GATEWARE) $(FIRMWARE)

SRC = $(TOP_SRC)
$(BIOS_FILE): $(SRC)
	python3 $< --no-compile-gateware

$(FIRMWARE): $(BIOS_FILE)
	$(MAKE) -C firmware

$(GATEWARE): $(BIOS_FILE)
	python3 $(TOP_SRC) $(ARGS) --build

bios: $(BIOS_FILE)
firmware: $(FIRMWARE)
gateware: $(GATEWARE)

load:
	python3 load.py --bit_file=$(GATEWARE)

flash: $(FIRMWARE)
	python3 $(TOP_SRC) $(ARGS) --flash

UART_PORT = /dev/cu.usbserial-0000162
boot:
	litex_term $(UART_PORT) --serial-boot --kernel=$(FIRMWARE)

clean:
	rm -rf build