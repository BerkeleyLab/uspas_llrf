.PHONY: all load clean flash

BOARD = marble
TOP_SRC = $(BOARD).py

ARGS = --with-etherbone \
		--csr-csv build/csr.csv \

ifeq ($(BOARD), arty_a7)
	ARGS += --variant a7-100
endif
ifeq ($(BOARD), marble)
	ARGS += --with-bist
	ARGS += --spd-dump targets/sdram_spd.txt
endif

all: $(TOP_SRC)
	python $< $(ARGS) --build

load: $(TOP_SRC)
	python $< $(ARGS) --load

flash: $(TOP_SRC)
	python $< $(ARGS) --flash

clean:
	rm -rf build