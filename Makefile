# RV32IM five-stage core - top-level targets
#
#   make lint        Verilator -Wall lint of the RTL
#   make sim         build the Verilator models (BP_MODE 0/1/2) and the single-cycle reference
#   make unit        cocotb unit tests (ALU, register file, mul/div, decoder)
#   make isa         riscv-tests rv32ui/rv32um on the five-stage core and the ISS
#   make riscof      riscv-arch-test I + M via RISCOF (DUT vs Spike)
#   make lockstep    CoreMark + 600 random programs, compared against Spike per instruction
#   make coremark    CoreMark in simulation with the CPI breakdown
#   make regress     all of the above
#
# Needs: verilator (5.x), riscv64-unknown-elf-gcc, python3 + cocotb, spike, riscof.

SPIKE ?= spike
export SPIKE

all: sim

lint:
	$(MAKE) -C tb/verilator lint

sim:
	$(MAKE) -C tb/verilator BP_MODE=0
	$(MAKE) -C tb/verilator BP_MODE=1
	$(MAKE) -C tb/verilator BP_MODE=2
	$(MAKE) -C tb/sc

unit:
	$(MAKE) -C tb/unit

isa: sim
	$(MAKE) -C tests run
	$(MAKE) -C tests run-sc
	python3 tools/run_tests.py --sim spike tests/build/*.elf

riscof:
	$(MAKE) -C tests/riscof

lockstep: sim
	$(MAKE) -C sw/coremark lockstep
	python3 tb/lockstep/run_lockstep.py --random 600 --seed 1

coremark: sim
	$(MAKE) -C sw/coremark sim

irq: sim
	$(MAKE) -C sw/tests/timer_irq
	tb/verilator/obj_dir_bp2/Vsoc_top +imem=sw/tests/timer_irq/build/timer_irq.imem.hex \
	    +dmem=sw/tests/timer_irq/build/timer_irq.dmem.hex

regress: lint unit isa irq riscof lockstep coremark

clean:
	$(MAKE) -C tb/verilator clean
	$(MAKE) -C tb/sc clean
	$(MAKE) -C tb/unit clean
	$(MAKE) -C tests clean
	$(MAKE) -C tests/riscof clean
	$(MAKE) -C sw/hello clean
	$(MAKE) -C sw/coremark clean
	rm -rf sw/coremark/build_lockstep tb/lockstep/work

.PHONY: all lint sim unit isa riscof lockstep coremark irq regress clean
