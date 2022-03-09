.PHONY: all load clean

all:
	python top.py --with-ethernet --build

load:
	python top.py --load

clean:
	rm -rf build