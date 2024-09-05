# substitute for a real build system integration
set -e
BLOCK_RAM_SIZE=32768  # match soc/marble_zest/common/common.mk
make VIVADO_CMD=false || true  # need dependencies for bitfile, not the bitfile itself
SYSTEM32=../../soc/marble_zest/synth/system32.dat
test -r $SYSTEM32 && cp $SYSTEM32 .

# Generate dependency file topsim.d
DEF_CONFG="-DSIMULATE -DBLOCK_RAM_SIZE=$BLOCK_RAM_SIZE"
INC_PATHS="-I../../llrf_dsp -I../../marble_bsp/_autogen -I../../llrf_dsp/_autogen"
SRC_PATHS="-y ../../llrf_dsp -y ../../marble_bsp -y ../../submodules/bedrock/badger -y ../../submodules/bedrock/dsp -y ../../submodules/bedrock/soc/picorv32/gateware -y ../../submodules/bedrock/cordic -y ../../submodules/bedrock/serial_io/EVG_EVR -y ../../submodules/bedrock/localbus -y ../../submodules/bedrock/homeless"
SRC_V="marble_zest_frame.v config_romx.v ../../soc/marble_zest/common/system.v ../../submodules/bedrock/projects/test_marble_family/mmc_mailbox.v ../../submodules/bedrock/badger/tests/spi_gate.v ../../submodules/bedrock/serial_io/simpleuart.v"
iverilog -Wall -Wno-timescale -g 2005-sv $DEF_CONFG $INC_PATHS $SRC_PATHS -o /dev/null -Mtopsim.d $SRC_V
TOP_V=$(uniq < topsim.d | grep "\.v$" | tr '\n' ' ')

# Verilate the design
# top levels are topsim.cpp and marble_zest_frame.v
if true; then
ETH_C="../../submodules/bedrock/badger/tests/ethernet_model.c ../../submodules/bedrock/badger/tests/tap_alloc.c ../../submodules/bedrock/badger/tests/crc32.c"
VLATOR_LINT_IGNORE="-Wno-WIDTH -Wno-TIMESCALEMOD -Wno-PINMISSING -Wno-REDEFMACRO"
verilator --trace-fst -CFLAGS "-Wno-logical-op -I ../../../submodules/bedrock/badger/tests" -cc --exe $VLATOR_LINT_IGNORE $DEF_CONFG $INC_PATHS --top marble_zest_frame -timing topsim.cpp $ETH_C $TOP_V

# Build actual executable Vmarble_zest_frame
MAKEFLAGS="" make -C obj_dir -f Vmarble_zest_frame.mk
mv obj_dir/Vmarble_zest_frame .
ls -l Vmarble_zest_frame
echo "DONE -- ready for ./Vmarble_zest_frame and ping 192.168.7.123"
# (IP set in marble_zest_frame.v)
# also, in uspas_llrf/python you can
# python3 test.py leep://192.168.7.123:803 list
fi

# Optional follow-on: run cdc_snitch
if test "$1" = "cdc_snitch"; then
  cp system32.dat system32.hex
  yosys -q -p "read_verilog -I../../llrf_dsp -I../../marble_bsp/_autogen -I../../llrf_dsp/_autogen -DSKIP_XILINX -DBUGGY_FORLOOP -DBLOCK_RAM_SIZE=24576 $TOP_V ../../submodules/bedrock/dsp/shortfifo.v ../../submodules/bedrock/dsp/half_filt.v ../../submodules/bedrock/dsp/sat_add.v; script ../../submodules/bedrock/build-tools/cdc_snitch_proc.ys; write_json topsim_yosys.json"
  python3 ../../submodules/bedrock/build-tools/cdc_snitch.py topsim_yosys.json -o topsim_cdc.txt
fi
