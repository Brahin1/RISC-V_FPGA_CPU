# Build riscv-tests (rv32ui-p) against the TCM environment in env/
#
#   make            build all tests into build/
#   make run-sc     run rv32ui on the single-cycle reference core
#
# fence_i and ma_data are not built:
#   fence_i  executes freshly stored code out of the data section; the core is
#            Harvard (IMEM is not reachable from the data port)
#   ma_data  expects misaligned loads/stores to be handled; this core raises
#            the misaligned-access exception instead (allowed by the spec)

ROOT   := $(abspath ..)
RT     := $(ROOT)/tests/riscv-tests/isa
CROSS  ?= riscv64-unknown-elf-
CC     := $(CROSS)gcc

CFLAGS := -march=rv32im_zicsr -mabi=ilp32 -static -mcmodel=medany -fvisibility=hidden \
          -nostdlib -nostartfiles -I$(ROOT)/tests/env -I$(RT)/macros/scalar \
          -T$(ROOT)/tests/env/link.ld

RV32UI := simple add addi and andi auipc beq bge bgeu blt bltu bne jal jalr \
          lb lbu lh lhu lw ld_st lui or ori sb sh sw st_ld sll slli slt slti \
          sltiu sltu sra srai srl srli sub xor xori

TESTS  := $(addprefix rv32ui-p-,$(RV32UI))
ELFS   := $(addprefix build/,$(addsuffix .elf,$(TESTS)))

all: $(ELFS)

build/rv32ui-p-%.elf: $(RT)/rv32ui/%.S env/riscv_test.h | build
	$(CC) $(CFLAGS) $< -o $@
	python3 $(ROOT)/tools/elf2hex.py $@ --out build/rv32ui-p-$*

build:
	mkdir -p build

run-sc: all
	python3 $(ROOT)/tools/run_tests.py --sim single-cycle $(filter build/rv32ui%,$(ELFS))

clean:
	rm -rf build

.PHONY: all run-sc clean
