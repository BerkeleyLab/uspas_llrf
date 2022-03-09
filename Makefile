.PHONY: all load clean flash

ARGS = --variant a7-100 --with-etherbone \
		--eth-ip 192.168.19.50 \
		--csr-csv csr.csv

all:
	python arty_a7.py $(ARGS) --build

load:
	python arty_a7.py $(ARGS) --load

flash:
	python arty_a7.py $(ARGS) --flash

clean:
	rm -rf build