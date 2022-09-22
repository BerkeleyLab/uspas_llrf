.PHONY: all load clean flash

# TOP_SRC = arty_a7.py
TOP_SRC = marble.py
ARGS = --with-etherbone \
		--with-bist \
		--csr-csv build/csr.csv \
		# --variant a7-100

all:
	python $(TOP_SRC) $(ARGS) --build

load:
	python $(TOP_SRC) $(ARGS) --load

flash:
	python $(TOP_SRC) $(ARGS) --flash

clean:
	rm -rf build