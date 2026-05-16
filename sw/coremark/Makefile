# CoreMark on the RV32IM core
#
#   make                      ITERATIONS=10 (simulation-sized)
#   make ITERATIONS=3000      hardware run (>= 10 s at 150 MHz)
#   make sim                  run on the Verilator model and report CPI
#
# CoreMark sources come from the eembc/coremark submodule; only the port
# files in port/ are ours.

PROG       := coremark
ITERATIONS ?= 10
CM         := coremark

OPT        := -O2
CFLAGS     := $(OPT) -DITERATIONS=$(ITERATIONS) -DPERFORMANCE_RUN=1 -DTOTAL_DATA_SIZE=2000 \
              -DFLAGS_STR='"$(OPT)"' -I$(CM) -Iport -Wno-implicit-function-declaration

SRCS       := $(CM)/core_list_join.c $(CM)/core_main.c $(CM)/core_matrix.c \
              $(CM)/core_state.c $(CM)/core_util.c port/core_portme.c port/ee_printf.c

include ../common/common.mk

SIM ?= $(ROOT)/tb/verilator/obj_dir_bp1/Vsoc_top

sim: all
	$(SIM) +imem=$(BUILD)/$(PROG).imem.hex +dmem=$(BUILD)/$(PROG).dmem.hex | tee $(BUILD)/sim.log
	python3 $(TOOLS)/cpi_report.py $(BUILD)/sim.log

.PHONY: sim
