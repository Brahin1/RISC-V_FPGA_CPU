# Verilator build of soc_top
#   make            -> obj_dir/Vsoc_top
#   make TRACE=1    -> with VCD support (+vcd=wave.vcd)
#   make BP_MODE=0  -> static not-taken fetch (1 = BTFN)
#   make lint

ROOT    := $(abspath ../..)
RTL_DIR := $(ROOT)/rtl
RTL     := $(addprefix $(RTL_DIR)/, core_pkg.sv alu.sv regfile.sv decoder.sv muldiv.sv \
             csr.sv branch_predictor.sv hazard_unit.sv if_stage.sv id_stage.sv \
             ex_stage.sv mem_stage.sv wb_stage.sv core_top.sv tcm.sv mmio.sv soc_top.sv)

BP_MODE ?= 1
TRACE   ?= 0
OBJ     ?= obj_dir_bp$(BP_MODE)

VFLAGS  := --cc --exe --build -j 0 -O3 --x-assign fast --x-initial fast \
           -Wno-fatal -Wno-UNUSED -I$(RTL_DIR) --top-module soc_top -GBP_MODE=$(BP_MODE) \
           --Mdir $(OBJ) -CFLAGS -O2
ifeq ($(TRACE),1)
VFLAGS  += --trace
endif

SIM := $(OBJ)/Vsoc_top

all: $(SIM)

$(SIM): $(RTL) sim_main.cpp
	verilator $(VFLAGS) $(RTL) sim_main.cpp

lint:
	verilator --lint-only -Wall -I$(RTL_DIR) $(RTL) --top-module soc_top

clean:
	rm -rf obj_dir*

.PHONY: all lint clean
