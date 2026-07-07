# RV32IM five-stage RISC-V core

An in-order RV32IM + Zicsr processor written from scratch in SystemVerilog, verified against the official RISC-V test suites and against Spike instruction by instruction, and benchmarked with CoreMark. The SoC wrapper targets the Zynq-7020 programmable logic: the core runs out of two BRAM TCMs whose second ports are reachable from the ARM, so the PS can load programs and read results.

- **ISA:** RV32I + M + Zicsr, machine mode only, precise exceptions, machine timer interrupt
- **Pipeline:** IF / ID / EX / MEM / WB, full operand forwarding, 1-cycle load-use interlock
- **Multiply:** 33x33 signed multiply split over EX -> MEM (maps onto DSP48E1s), result forwardable from WB
- **Divide:** iterative radix-2 restoring divider, 33-cycle stall, spec-defined divide-by-zero and overflow results
- **Branch prediction:** 64-entry BTB with 2-bit counters (static not-taken and BTFN also selectable)
- **Memory:** 32 KB IMEM + 32 KB DMEM tightly-coupled BRAM, single-cycle, no caches, so cycle counts are deterministic

## Results

All numbers below come from the Verilator model of `soc_top`.

| Metric | Value |
|---|---|
| riscv-tests (`rv32ui-p`, `rv32um-p`) | **48 / 48** pass |
| riscv-arch-test via RISCOF (`rv32i_m/I`, `rv32i_m/M`) | **47 / 47** signatures match Spike |
| Lockstep vs. Spike | **12.5 M** retired instructions compared (CoreMark + 600 random programs), **0 divergences** |
| cocotb unit tests | 11 tests, ALU: 10 ops x 10k random vectors + corners, 0 mismatches |
| CoreMark/MHz | **2.857** (GCC 13.2, `-O2`, 10 iterations) |
| CPI on CoreMark | **1.117** |
| Branch prediction accuracy (CoreMark) | **90.1 %** |

### Branch prediction

Same CoreMark binary, only `BP_MODE` changed:

| | static not-taken | BTFN | BTB + 2-bit |
|---|---|---|---|
| Prediction accuracy | 44.2 % | 81.5 % | 90.1 % |
| CPI | 1.219 | 1.136 | 1.117 |
| CoreMark/MHz | 2.617 | 2.809 | 2.857 |

### CPI breakdown (CoreMark, BTB + 2-bit)

Produced by `tools/cpi_report.py` from the hardware performance counters (`mhpmcounter3-8`):

```
component                     cycles      CPI
---------------------------------------------
base (1 instr/cycle)         3133385    1.000
branch mispredicts             57857    0.018
jump redirects                 11055    0.004
load-use interlocks           203289    0.065
mul/div stalls                 93960    0.030
other (traps, fill)                0    0.000
---------------------------------------------
total                        3499546    1.117
```

With a good predictor in place, load-use interlocks are the largest remaining loss, followed by the iterative divider.

## Microarchitecture

```
        +------+     +------+     +------+     +-------+     +------+
  BTB ->|  IF  |---->|  ID  |---->|  EX  |---->|  MEM  |---->|  WB  |
        | PC   |     |decode|     | ALU  |     | load  |     |rd wr |
        | IMEM |     |regs  |     |branch|     | MUL p |     |retire|
        +------+     +------+     |AGU   |     | CSR   |     +------+
           ^            ^         |DIV   |     | traps |        |
           |            |         +------+     +-------+        |
           |            |          ^  ^ |          |  |         |
           |            |          |  | +-- EX/MEM fwd           |
           |            |          |  +---- MEM/WB fwd ----------+
           |            +-- load-use / mul-use interlock
           +-- redirect: EX mispredict (1 cycle), MEM trap / MRET
```

- **Fetch.** IMEM is a synchronous BRAM addressed with the *next* PC, so the BRAM output register doubles as the IF/ID instruction register. The predictor is looked up with the PC of the instruction that just arrived in ID, which makes a correct taken prediction free.
- **Forwarding.** Two 3:1 muxes per EX operand: EX/MEM (results produced in EX: ALU, PC+4, DIV) and MEM/WB (everything). WB -> ID is covered by a write-through register file read. Writes to `x0` are dropped at decode, so they are never forwarded.
- **Interlocks.** Loads, MUL and CSR reads produce their value in MEM. A dependent instruction directly behind one of them waits one cycle in ID.
- **Branches.** Resolved in EX. A misprediction redirects fetch and squashes the single instruction in ID, so the penalty is 1 cycle. Non-control instructions that hit in the BTB by aliasing are corrected the same way.
- **Precise exceptions.** MEM is the commit point. Decode-time exceptions (illegal, ECALL, EBREAK) and EX-time exceptions (misaligned load/store, misaligned jump target) ride down the pipe and are taken in MEM, where CSR writes also happen. Older instructions have already left MEM, younger ones are flushed, and the only store that could be younger is blocked in EX in the same cycle.
- **Interrupts.** A pending enabled timer interrupt tags the instruction in ID, which never executes and becomes `mepc`. If an older CSR write disables the interrupt before the tag reaches MEM, the instruction is replayed instead.
- **Retire port.** RVFI-style record per retired instruction (`pc`, `insn`, `rd`, `rd_wdata`, memory address, mask and data). The lockstep checker consumes it in simulation.

### Memory map (core view)

| Address | Size | Contents |
|---|---|---|
| `0x0000_0000` | 32 KB | IMEM (fetch only; PS writes it through port A) |
| `0x0001_0000` | 32 KB | DMEM (`.rodata`, `.data`, `.bss`, stack) |
| `0x1000_0000` | 8 B | `tohost`: 1 = pass, `(n << 1) \| 1` = fail with code n |
| `0x1000_0008` | 4 B | console: byte goes into a 256-entry FIFO the PS drains |
| `0x1000_0010` | 8 B | `mtime` |
| `0x1000_0018` | 8 B | `mtimecmp` |
| `0x1000_0020` | 4 B | LED register |

`tohost` is 8 bytes wide so the same ELF also terminates correctly on Spike, whose HTIF treats `tohost` as a 64-bit location.

### CSRs

`mstatus`, `misa`, `mie`, `mip`, `mtvec` (direct mode), `mscratch`, `mepc`, `mcause`, `mtval`, `mcycle[h]`, `minstret[h]`, the `cycle`/`instret` aliases, and `mhpmcounter3-8`:

| Counter | Event |
|---|---|
| `mhpmcounter3` | load-use interlock cycles |
| `mhpmcounter4` | conditional branch mispredicts |
| `mhpmcounter5` | JAL/JALR redirects |
| `mhpmcounter6` | mul-use interlock + divider stall cycles |
| `mhpmcounter7` | conditional branches executed |
| `mhpmcounter8` | traps taken |

## Verification

| Layer | Where | What it covers |
|---|---|---|
| Unit tests | `tb/unit` (cocotb) | ALU, register file, MUL pipeline + divider (incl. ÷0, `INT_MIN / -1`, flush mid-divide), decoder legality over 40k random words |
| Directed ISA tests | `tests/` | riscv-tests `rv32ui-p-*`, `rv32um-p-*` on the five-stage core, on the single-cycle reference (rv32ui) and on Spike |
| Compliance | `tests/riscof` | riscv-arch-test I and M suites, memory signatures compared against Spike |
| Lockstep | `tb/lockstep` | retire port vs. Spike `--log-commits` (or the Python ISS) on every retired instruction: PC, instruction, rd value, load/store address, store data |
| Random programs | `tb/lockstep/rand_gen.py` | dependency chains, load-use and mul-use pairs, branches shadowing branches, JAL/JALR, ÷0 and overflow, CSR RMW with `rs1 = x0`, ECALL/EBREAK/illegal into a handler, all inside loops so the predictor trains and mispredicts |
| Interrupts | `sw/tests/timer_irq` | 20 timer interrupts landing at arbitrary points of a running loop |

Spike runs with `--disable-dtb --priv=m --isa=rv32im_zicsr` and the same memory regions as the SoC, so the same ELF runs unchanged on both.

`fence_i` and `ma_data` from riscv-tests are not run: the core is Harvard (code cannot be written through the data port) and raises the misaligned-access exception rather than splitting misaligned accesses, which the spec allows. For the same Harvard reason only the I and M arch-test suites are run; the privilege suite's trap framework reads tables out of `.text` with loads.

## Repo layout

```
rtl/            core_pkg, alu, regfile, decoder, muldiv, csr, branch_predictor, hazard_unit,
                if/id/ex/mem/wb stages, core_top, tcm, mmio, soc_top, lint.vlt
rtl/single_cycle/  single-cycle RV32I reference core
tb/verilator/   C++ harness for soc_top (console, tohost, retire trace, VCD)
tb/sc/          harness for the single-cycle core
tb/unit/        cocotb unit tests
tb/iss/         Python ISS (reference model for unit tests and an alternative lockstep reference)
tb/lockstep/    trace comparator, random program generator, lockstep runner
sw/common/      crt0, linker script, console + counter helpers
sw/hello/       first program
sw/coremark/    CoreMark port (EEMBC sources as a submodule)
sw/tests/       directed tests (timer interrupt)
tests/          riscv-tests environment for this memory map; riscv-tests and riscv-arch-test submodules
tests/riscof/   RISCOF config, DUT plugin and Spike reference plugin
tools/          elf2hex.py, run_tests.py, cpi_report.py
```

## Getting started

Tools: Verilator 5.x, `riscv64-unknown-elf-gcc` with rv32im multilib, Python 3 with `cocotb` and `riscof`, Spike.

```sh
git clone --recursive <repo>
make sim          # Verilator models
make isa          # riscv-tests
make unit         # cocotb
make lockstep     # CoreMark + 600 random programs vs. Spike
make riscof       # arch tests
make coremark     # CoreMark + CPI breakdown
make regress      # everything
```

Run any program by hand:

```sh
make -C sw/hello
tb/verilator/obj_dir_bp2/Vsoc_top +imem=sw/hello/build/hello.imem.hex +dmem=sw/hello/build/hello.dmem.hex
```

Plusargs: `+trace=<file>` writes the retire trace, `+vcd=<file>` dumps waves (build with `TRACE=1`), `+max_cycles=<n>`.

## Not in scope

Caches, an MMU and supervisor/user modes, the A/F/C extensions, self-modifying code (`FENCE.I` is a no-op).

## References

- RISC-V unprivileged and privileged specifications
- riscv-tests, riscv-arch-test + RISCOF, Spike (riscv-isa-sim)
- EEMBC CoreMark
- Harris & Harris, *Digital Design and Computer Architecture: RISC-V Edition*
