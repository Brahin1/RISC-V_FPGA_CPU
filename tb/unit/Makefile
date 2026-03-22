# cocotb unit tests (Verilator)
#
#   make            run all
#   make alu        run one (alu | regfile)
#
# Each test module compares the RTL against the reference functions in
# tb/iss/rv32iss.py.

ROOT := $(abspath ../..)
RTL  := $(ROOT)/rtl

TESTS := alu regfile

all: $(TESTS)

$(TESTS):
	$(MAKE) -f cocotb.mk TOPLEVEL=$(TOP_$@) MODULE=test_$@ SIM_BUILD=sim_build_$@ \
	        VERILOG_SOURCES="$(SRC_$@)"

TOP_alu     := alu
TOP_regfile := regfile

SRC_alu     := $(RTL)/core_pkg.sv $(RTL)/alu.sv
SRC_regfile := $(RTL)/regfile.sv

clean:
	rm -rf sim_build_* results.xml __pycache__ *.vcd

.PHONY: all clean $(TESTS)
