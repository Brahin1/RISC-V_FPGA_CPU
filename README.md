# RV32IM five-stage RISC-V core

An in-order RV32IM + Zicsr processor written from scratch in SystemVerilog, verified against the official RISC-V test suites and against Spike instruction by instruction. The SoC wrapper targets the Zynq-7020 programmable logic: the core runs out of two BRAM TCMs whose second ports are reachable from the ARM, so the PS can load programs and read results.

- **ISA:** RV32I + M + Zicsr, machine mode only, precise exceptions, machine timer interrupt
- **Pipeline:** IF / ID / EX / MEM / WB, full operand forwarding, 1-cycle load-use interlock
- **Multiply:** 33x33 signed multiply split over EX -> MEM (maps onto DSP48E1s), result forwardable from WB
- **Divide:** iterative radix-2 restoring divider, 33-cycle stall, spec-defined divide-by-zero and overflow results
- **Branch prediction:** static not-taken or BTFN (`BP_MODE`)
- **Memory:** 32 KB IMEM + 32 KB DMEM tightly-coupled BRAM, single-cycle, no caches, so cycle counts are deterministic

## Status

- riscv-tests `rv32ui-p` + `rv32um-p`: 48/48 on the pipeline, rv32ui 40/40 on the single-cycle reference
- lockstep against Spike clean on CoreMark-sized random program batches
- next: performance counters, CoreMark, RISCOF, BTB

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

`mstatus`, `misa`, `mie`, `mip`, `mtvec` (direct mode), `mscratch`, `mepc`, `mcause`, `mtval`, `mcycle[h]`, `minstret[h]`, the `cycle`/`instret` aliases.

## Getting started

Tools: Verilator 5.x, `riscv64-unknown-elf-gcc` with rv32im multilib, Python 3 with `cocotb` and `riscof`, Spike.

```sh
git clone --recursive <repo>
make sim          # Verilator models
make isa          # riscv-tests
make unit         # cocotb
```

Run any program by hand:

```sh
make -C sw/hello
tb/verilator/obj_dir_bp2/Vsoc_top +imem=sw/hello/build/hello.imem.hex +dmem=sw/hello/build/hello.dmem.hex
```

Plusargs: `+trace=<file>` writes the retire trace, `+vcd=<file>` dumps waves (build with `TRACE=1`), `+max_cycles=<n>`.

