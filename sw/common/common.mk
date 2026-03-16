# common.mk - shared build rules for programs under sw/
#   include from a program Makefile after setting PROG and SRCS

ROOT     ?= $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)
COMMON   := $(ROOT)/sw/common
TOOLS    := $(ROOT)/tools

CROSS    ?= riscv64-unknown-elf-
CC       := $(CROSS)gcc
OBJDUMP  := $(CROSS)objdump

ARCH     := -march=rv32im_zicsr -mabi=ilp32
CFLAGS   ?= -O2
CFLAGS   += $(ARCH) -ffreestanding -fno-builtin-printf -nostdlib -static \
            -mcmodel=medany -Wall -I$(COMMON)
LDFLAGS  += $(ARCH) -nostdlib -nostartfiles -static -T $(COMMON)/link.ld -Wl,--gc-sections

BUILD    ?= build
OBJS     := $(BUILD)/crt0.o $(BUILD)/console.o $(BUILD)/libc_min.o \
            $(patsubst %.c,$(BUILD)/%.o,$(patsubst %.S,$(BUILD)/%.o,$(notdir $(SRCS))))

vpath %.c $(COMMON) $(sort $(dir $(SRCS)))
vpath %.S $(COMMON) $(sort $(dir $(SRCS)))

all: $(BUILD)/$(PROG).elf $(BUILD)/$(PROG).imem.hex $(BUILD)/$(PROG).dis

$(BUILD):
	mkdir -p $@

$(BUILD)/%.o: %.c | $(BUILD)
	$(CC) $(CFLAGS) -ffunction-sections -fdata-sections -c $< -o $@

$(BUILD)/%.o: %.S | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/$(PROG).elf: $(OBJS)
	$(CC) $(LDFLAGS) $^ -lgcc -o $@

$(BUILD)/$(PROG).imem.hex: $(BUILD)/$(PROG).elf
	python3 $(TOOLS)/elf2hex.py $< --out $(BUILD)/$(PROG)

$(BUILD)/$(PROG).dis: $(BUILD)/$(PROG).elf
	$(OBJDUMP) -d $< > $@

clean:
	rm -rf $(BUILD)

.PHONY: all clean
