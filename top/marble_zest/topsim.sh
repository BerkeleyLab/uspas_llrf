# substitute for a real build system integration
set -e
BLOCK_RAM_SIZE=24576  # match soc/marble_zest/common/common.mk
make VIVADO_CMD=false || true  # need dependencies for bitfile, not the bitfile itself

DEF_CONFG="-DSIMULATE -DBLOCK_RAM_SIZE=$BLOCK_RAM_SIZE"
INC_PATHS="-I../../llrf_dsp -I../../marble_bsp/_autogen -I../../llrf_dsp/_autogen"
SRC_PATHS="-y ../../llrf_dsp -y ../../marble_bsp -y ../../submodules/bedrock/badger -y ../../submodules/bedrock/dsp -y ../../submodules/bedrock/soc/picorv32/gateware -y ../../submodules/bedrock/cordic -y ../../submodules/bedrock/serial_io/EVG_EVR -y ../../submodules/bedrock/localbus -y ../../submodules/bedrock/homeless"
SRC_V="marble_zest_frame.v config_romx.v ../../soc/marble_zest/common/system.v ../../submodules/bedrock/projects/test_marble_family/mmc_mailbox.v ../../submodules/bedrock/badger/tests/spi_gate.v ../../submodules/bedrock/serial_io/simpleuart.v"
iverilog -Wall -Wno-timescale -g 2005-sv $DEF_CONFG $INC_PATHS $SRC_PATHS -o /dev/null -Mtopsim.d $SRC_V

TOP_V=$(uniq < topsim.d | grep "\.v$")
ETH_C="../../submodules/bedrock/badger/tests/ethernet_model.c ../../submodules/bedrock/badger/tests/tap_alloc.c ../../submodules/bedrock/badger/tests/crc32.c"
VLATOR_LINT_IGNORE="-Wno-WIDTH -Wno-TIMESCALEMOD -Wno-PINMISSING -Wno-REDEFMACRO"
verilator --trace -CFLAGS "-Wno-logical-op -I ../../../submodules/bedrock/badger/tests" -cc --exe $VLATOR_LINT_IGNORE $DEF_CONFG $INC_PATHS --top marble_zest_frame -timing topsim.cpp $ETH_C $TOP_V

MAKEFLAGS="" make -C obj_dir -f Vmarble_zest_frame.mk
mv obj_dir/Vmarble_zest_frame .
ls -l Vmarble_zest_frame
echo DONE
# still missing: instructions for system32.hex, generated in ../../soc/marble_zest/synth/ ?

# test with ./Vmarble_zest_frame
# ping 192.168.7.123 (IP set in marble_zest_frame.v)
# in uspas_llrf/python
# python3 test.py leep://192.168.7.123:803 list
