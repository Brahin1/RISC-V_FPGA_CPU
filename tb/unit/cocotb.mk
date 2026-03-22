# invoked from Makefile with TOPLEVEL / MODULE / VERILOG_SOURCES set
SIM              ?= verilator
TOPLEVEL_LANG    ?= verilog
EXTRA_ARGS       += -Wno-fatal -Wno-UNUSED -Wno-WIDTH
export PYTHONPATH := $(abspath ../iss):$(PYTHONPATH)
include $(shell cocotb-config --makefiles)/Makefile.sim
