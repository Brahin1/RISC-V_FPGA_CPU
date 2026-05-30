# riscv-arch-test compliance via RISCOF: rv32im_core (DUT) vs Spike (reference)
#
#   make        build the large-memory simulator, run rv32i_m/I and rv32i_m/M
#
# Only the I and M suites are run. The privilege suite's trap framework reads
# tables out of .text with ordinary loads, which this Harvard TCM core cannot
# do (IMEM is not on the data port).

ROOT   := $(abspath ../..)
SUITE  := $(ROOT)/tests/riscv-arch-test/riscv-test-suite
SPIKE  ?= spike

all: run

sim:
	$(MAKE) -C $(ROOT)/tb/verilator riscof

run: sim
	riscof run --config=config.ini --suite=$(SUITE)/rv32i_m/I --env=$(SUITE)/env \
	      --work-dir=riscof_work_I --no-browser 2>&1 | tee riscof_I.log | grep -E "Passed|Failed"
	riscof run --config=config.ini --suite=$(SUITE)/rv32i_m/M --env=$(SUITE)/env \
	      --work-dir=riscof_work_M --no-browser 2>&1 | tee riscof_M.log | grep -E "Passed|Failed"
	@echo; echo "I: $$(grep -c ': Passed' riscof_I.log) passed, $$(grep -c ': Failed' riscof_I.log) failed"
	@echo "M: $$(grep -c ': Passed' riscof_M.log) passed, $$(grep -c ': Failed' riscof_M.log) failed"

clean:
	rm -rf riscof_work* riscof_*.log

.PHONY: all sim run clean
