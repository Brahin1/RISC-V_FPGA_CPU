#!/usr/bin/env python3
"""rand_gen.py - random RV32IM program generator for lockstep testing.

The generated programs are meant to hit pipeline corner cases rather than to
compute anything:

  * operands are biased toward recently written registers, so most
    instructions depend on the one or two before them (forwarding paths)
  * load -> use and mul -> use pairs back to back (interlocks)
  * short forward branches, branches into branches, JAL/JALR (redirect + flush)
  * divides by zero and INT_MIN / -1
  * CSR read-modify-write on mscratch, including the rs1 = x0 forms
  * ECALL / EBREAK / illegal instructions into a handler that skips them
  * every block runs in a loop so the branch predictor trains and mispredicts

Reserved registers: x8 (s0) = data buffer base, x9 (s1) = loop counter,
x31 (t6) = trap handler scratch.
"""

import argparse
import random

DATA_BUF = 0x0001_0000          # start of DMEM
DATA_SIZE = 2048

RESERVED = {0, 8, 9, 31}
REGS = [r for r in range(32) if r not in RESERVED]

ALU_RR = ["add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"]
ALU_RI = ["addi", "slti", "sltiu", "xori", "ori", "andi"]
SHIFT_I = ["slli", "srli", "srai"]
MULDIV = ["mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu"]
BRANCH = ["beq", "bne", "blt", "bge", "bltu", "bgeu"]
LOADS = [("lb", 1), ("lbu", 1), ("lh", 2), ("lhu", 2), ("lw", 4)]
STORES = [("sb", 1), ("sh", 2), ("sw", 4)]
INTERESTING = [0, 1, -1, 0x7FFFFFFF, -0x80000000, 0x80, 0xFF, 0x8000, 0xFFFF, 31, 32, -2048, 2047]


class Gen:
    def __init__(self, seed, blocks, block_len, max_iters, traps):
        self.rng = random.Random(seed)
        self.seed = seed
        self.blocks = blocks
        self.block_len = block_len
        self.max_iters = max_iters
        self.traps = traps
        self.lines = []
        self.recent = []
        self.label_id = 0

    # -- helpers ---------------------------------------------------------------
    def emit(self, s):
        self.lines.append("    " + s)

    def label(self):
        self.label_id += 1
        return f"L{self.label_id}"

    def src(self):
        if self.recent and self.rng.random() < 0.6:
            return self.rng.choice(self.recent[-3:])
        return self.rng.choice(REGS)

    def dst(self):
        r = self.rng.choice(REGS)
        self.recent.append(r)
        if len(self.recent) > 8:
            self.recent.pop(0)
        return r

    def imm12(self):
        if self.rng.random() < 0.3:
            return self.rng.choice([0, 1, -1, 2047, -2048])
        return self.rng.randint(-2048, 2047)

    # -- instruction classes -------------------------------------------------
    def alu(self):
        if self.rng.random() < 0.5:
            self.emit(f"{self.rng.choice(ALU_RR)} x{self.dst()}, x{self.src()}, x{self.src()}")
        elif self.rng.random() < 0.7:
            self.emit(f"{self.rng.choice(ALU_RI)} x{self.dst()}, x{self.src()}, {self.imm12()}")
        else:
            self.emit(f"{self.rng.choice(SHIFT_I)} x{self.dst()}, x{self.src()}, {self.rng.randint(0, 31)}")

    def upper(self):
        op = self.rng.choice(["lui", "auipc"])
        self.emit(f"{op} x{self.dst()}, {self.rng.randint(0, 0xFFFFF)}")

    def muldiv(self):
        op = self.rng.choice(MULDIV)
        a, b = self.src(), self.src()
        if op.startswith(("div", "rem")) and self.rng.random() < 0.25:
            # force a corner case
            if self.rng.random() < 0.5:
                b = self.dst()
                self.emit(f"li x{b}, 0")
            else:
                a, b = self.dst(), self.dst()
                self.emit(f"li x{a}, 0x80000000")
                self.emit(f"li x{b}, -1")
        d = self.dst()
        self.emit(f"{op} x{d}, x{a}, x{b}")
        if self.rng.random() < 0.4:      # dependent op right behind it
            self.emit(f"add x{self.dst()}, x{d}, x{self.src()}")

    def mem(self):
        if self.rng.random() < 0.5:
            op, w = self.rng.choice(STORES)
            off = self.rng.randrange(0, DATA_SIZE - 4, w)
            self.emit(f"{op} x{self.src()}, {off}(x8)")
        op, w = self.rng.choice(LOADS)
        off = self.rng.randrange(0, DATA_SIZE - 4, w)
        d = self.dst()
        self.emit(f"{op} x{d}, {off}(x8)")
        if self.rng.random() < 0.5:      # load-use
            self.emit(f"{self.rng.choice(ALU_RR)} x{self.dst()}, x{d}, x{self.src()}")

    def branch(self):
        lbl = self.label()
        self.emit(f"{self.rng.choice(BRANCH)} x{self.src()}, x{self.src()}, {lbl}")
        for _ in range(self.rng.randint(0, 3)):
            if self.rng.random() < 0.3:          # branch shadowed by a branch
                inner = self.label()
                self.emit(f"{self.rng.choice(BRANCH)} x{self.src()}, x{self.src()}, {inner}")
                self.alu()
                self.lines.append(f"{inner}:")
            else:
                self.alu()
        self.lines.append(f"{lbl}:")

    def jump(self):
        lbl = self.label()
        if self.rng.random() < 0.5:
            self.emit(f"jal x{self.dst()}, {lbl}")
        else:
            t = self.dst()
            self.emit(f"la x{t}, {lbl}")
            self.emit(f"jalr x{self.dst()}, 0(x{t})")
        for _ in range(self.rng.randint(0, 2)):
            self.alu()
        self.lines.append(f"{lbl}:")

    def csr(self):
        op = self.rng.choice(["csrrw", "csrrs", "csrrc", "csrrwi", "csrrsi", "csrrci"])
        if op.endswith("i"):
            uimm = self.rng.choice([0, self.rng.randint(1, 31)])
            self.emit(f"{op} x{self.dst()}, mscratch, {uimm}")
        else:
            rs = 0 if self.rng.random() < 0.3 else self.src()
            self.emit(f"{op} x{self.dst()}, mscratch, x{rs}")

    def trap(self):
        self.emit(self.rng.choice(["ecall", "ebreak", ".word 0x00000000", ".word 0xffffffff"]))

    # -- program ---------------------------------------------------------------
    def block(self):
        weights = [("alu", 40), ("upper", 4), ("muldiv", 10), ("mem", 20),
                   ("branch", 12), ("jump", 5), ("csr", 4)]
        if self.traps:
            weights.append(("trap", 2))
        kinds, w = zip(*weights)
        for _ in range(self.block_len):
            getattr(self, self.rng.choices(kinds, w)[0])()

    def program(self):
        out = [f"# generated by rand_gen.py, seed {self.seed}",
               "    .section .text.init",
               "    .globl _start",
               "_start:",
               "    la t6, trap_handler",
               "    csrw mtvec, t6",
               f"    li x8, 0x{DATA_BUF:08x}"]
        for r in REGS:
            out.append(f"    li x{r}, 0x{self.rng.getrandbits(32):08x}")
        # pre-fill the data buffer
        for off in range(0, DATA_SIZE, 64):
            out.append(f"    sw x{self.rng.choice(REGS)}, {off}(x8)")

        for _ in range(self.blocks):
            self.lines = []
            self.block()
            top = self.label()
            iters = self.rng.randint(1, self.max_iters)
            out.append(f"    li x9, {iters}")
            out.append(f"{top}:")
            out += self.lines
            out.append("    addi x9, x9, -1")
            out.append(f"    bnez x9, {top}")

        out += ["    li t6, 0x10000000",
                "    li x1, 1",
                "    sw x1, 0(t6)",
                "1:  j 1b",
                "",
                "    .align 2",
                "trap_handler:              # skip the faulting instruction",
                "    csrr t6, mepc",
                "    addi t6, t6, 4",
                "    csrw mepc, t6",
                "    csrr t6, mcause",
                "    csrr t6, mtval",
                "    mret"]
        return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--blocks", type=int, default=12)
    ap.add_argument("--block-len", type=int, default=40)
    ap.add_argument("--max-iters", type=int, default=40)
    ap.add_argument("--no-traps", action="store_true")
    ap.add_argument("-o", "--out", required=True)
    args = ap.parse_args()

    g = Gen(args.seed, args.blocks, args.block_len, args.max_iters, not args.no_traps)
    with open(args.out, "w") as f:
        f.write(g.program())


if __name__ == "__main__":
    main()
