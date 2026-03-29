# Single-cycle reference core (simulation only)
ROOT := $(abspath ../..)
RTL  := $(ROOT)/rtl/core_pkg.sv $(ROOT)/rtl/alu.sv $(ROOT)/rtl/regfile.sv $(ROOT)/rtl/decoder.sv \
        $(ROOT)/rtl/single_cycle/sc_core.sv sc_tb.sv

obj_dir/Vsc_tb: $(RTL) sc_main.cpp
	verilator --cc --exe --build -j 0 -O2 -Wno-fatal -Wno-UNUSED --top-module sc_tb $(RTL) sc_main.cpp

clean:
	rm -rf obj_dir
.PHONY: clean
