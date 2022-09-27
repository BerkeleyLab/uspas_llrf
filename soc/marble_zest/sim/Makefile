include ../../../dir_list.mk
include $(BUILD_DIR)/top_rules.mk
include $(APP_SOC_DIR)/common/common.mk

TARGET = system

# max. baudrate is F_CLK / 8
BOOTLOADER_BAUDRATE = 10416666
CFLAGS += -DSIMULATION
SRC_V  += $(VIVADO_BASE)/data/verilog/src/glbl.v
SRC_V  += $(COMMON_V) $(PICORV_DIR)/project/kc705/sim/i2c_model.v
SRC_V  += $(VIVADO_BASE)/data/verilog/src/unisims/XADC.v
SRC_V  += system_tb.v
OBJS   +=  0x000.lds

all: $(TARGET).vcd

$(TARGET).vcd: $(TARGET)32.hex
$(TARGET).elf: $(OBJS)
$(TARGET)_tb: $(SRC_V)

include $(BUILD_DIR)/bottom_rules.mk
