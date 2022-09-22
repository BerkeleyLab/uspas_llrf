.PHONY: all load clean flash

TOP_SRC = arty_a7.py
ARGS = --with-etherbone \
		--eth-ip 192.168.19.50 \
		--csr-csv csr.csv \
		--variant a7-100

all:
	python $(TOP_SRC) $(ARGS) --build

load:
	python $(TOP_SRC) $(ARGS) --load

flash:
	python $(TOP_SRC) $(ARGS) --flash

clean:
	rm -rf build