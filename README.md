# RV32IM five-stage RISC-V core

RV32IM + Zicsr core in SystemVerilog, targeting the Zynq-7020 PL with the ARM
as loader and console. Work in progress.

Plan:

- toolchain, crt0 / linker script, Python ISS
- single-cycle RV32I as a reference
- five-stage pipeline with forwarding, M extension, CSRs, precise exceptions
- verification: cocotb unit tests, riscv-tests, riscv-arch-test (RISCOF),
  lockstep against Spike, random programs
- CoreMark, performance counters, branch prediction
