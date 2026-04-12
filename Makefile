# RV32IM five-stage core - top-level targets
#
#   make lint        Verilator -Wall lint of the RTL
#   make sim         build the Verilator models and the single-cycle reference
#   make unit        cocotb unit tests
#   make isa         riscv-tests rv32ui/rv32um

all: sim

lint:
	$(MAKE) -C tb/verilator lint

sim:
	$(MAKE) -C tb/verilator
	$(MAKE) -C tb/sc

unit:
	$(MAKE) -C tb/unit

isa: sim
	$(MAKE) -C tests run
	$(MAKE) -C tests run-sc

clean:
	$(MAKE) -C tb/verilator clean
	$(MAKE) -C tb/sc clean
	$(MAKE) -C tb/unit clean
	$(MAKE) -C tests clean
	$(MAKE) -C sw/hello clean

.PHONY: all lint sim unit isa clean
