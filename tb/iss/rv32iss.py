#!/usr/bin/env python3
"""rv32iss.py - small RV32I + Zicsr instruction-set simulator.

Golden model for the RTL: the ALU reference function used by the unit tests
lives here, and ISS().run() executes a whole ELF.

Same memory map as the SoC: IMEM 0x0 (fetch only), DMEM 0x1_0000, MMIO 0x1000_0000.
Machine mode only, direct-mode mtvec, misaligned load/store/fetch trap.
"""

import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tools"))
import elf2hex  # noqa: E402

M32 = 0xFFFF_FFFF

IMEM_BASE, IMEM_SIZE = 0x0000_0000, 32 * 1024
DMEM_BASE, DMEM_SIZE = 0x0001_0000, 32 * 1024
MMIO_BASE = 0x1000_0000
TOHOST, CONSOLE, MTIME, MTIMECMP = 0x00, 0x08, 0x10, 0x18


def sext(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


def s32(v):
    return sext(v, 32)


# ---------------------------------------------------------------------------
# Reference functions shared with the unit tests
# ---------------------------------------------------------------------------
def alu(op, a, b):
    a &= M32
    b &= M32
    sh = b & 31
    return {
        "add":  (a + b),
        "sub":  (a - b),
        "sll":  (a << sh),
        "slt":  int(s32(a) < s32(b)),
        "sltu": int(a < b),
        "xor":  a ^ b,
        "srl":  a >> sh,
        "sra":  s32(a) >> sh,
        "or":   a | b,
        "and":  a & b,
    }[op] & M32


class Trap(Exception):
    def __init__(self, cause, tval=0):
        super().__init__(cause)
        self.cause, self.tval = cause, tval


class ISS:
    ALU_F3 = {0: "add", 1: "sll", 2: "slt", 3: "sltu", 4: "xor", 5: "srl", 6: "or", 7: "and"}

    def __init__(self):
        self.x = [0] * 32
        self.pc = 0
        self.imem = bytearray(IMEM_SIZE)
        self.dmem = bytearray(DMEM_SIZE)
        self.csr = {0x300: 0x1800, 0x304: 0, 0x305: 0, 0x340: 0, 0x341: 0, 0x342: 0, 0x343: 0}
        self.cycle = 0
        self.instret = 0
        self.mtimecmp = M32 | (M32 << 32)
        self.tohost = None
        self.console = bytearray()

    # -- loading -----------------------------------------------------------------
    def load_elf(self, path):
        entry, segs = elf2hex.read_segments(path)
        for addr, blob in segs:
            if IMEM_BASE <= addr < IMEM_BASE + IMEM_SIZE:
                self.imem[addr - IMEM_BASE:addr - IMEM_BASE + len(blob)] = blob
            elif DMEM_BASE <= addr < DMEM_BASE + DMEM_SIZE:
                self.dmem[addr - DMEM_BASE:addr - DMEM_BASE + len(blob)] = blob
        self.pc = entry

    # -- memory ----------------------------------------------------------------------
    def load(self, addr, size):
        if DMEM_BASE <= addr < DMEM_BASE + DMEM_SIZE:
            o = addr - DMEM_BASE
            return int.from_bytes(self.dmem[o:o + size], "little")
        if (addr & ~0xFF) == MMIO_BASE:
            off = addr & 0xFF
            mtime = self.cycle
            word = {MTIME: mtime & M32, MTIME + 4: mtime >> 32,
                    MTIMECMP: self.mtimecmp & M32, MTIMECMP + 4: self.mtimecmp >> 32}.get(off & ~3, 0)
            return (word >> (8 * (off & 3))) & ((1 << (8 * size)) - 1)
        return 0

    def store(self, addr, size, val):
        val &= (1 << (8 * size)) - 1
        if DMEM_BASE <= addr < DMEM_BASE + DMEM_SIZE:
            o = addr - DMEM_BASE
            self.dmem[o:o + size] = val.to_bytes(size, "little")
        elif (addr & ~0xFF) == MMIO_BASE:
            off = addr & 0xFF
            if off == TOHOST:
                self.tohost = val
            elif off == CONSOLE:
                self.console.append(val & 0xFF)
            elif off == MTIMECMP:
                self.mtimecmp = (self.mtimecmp & ~M32) | val
            elif off == MTIMECMP + 4:
                self.mtimecmp = (self.mtimecmp & M32) | (val << 32)

    def fetch(self, pc):
        if pc & 3:
            raise Trap(0, pc)
        if not (IMEM_BASE <= pc < IMEM_BASE + IMEM_SIZE):
            raise Trap(1, pc)
        return struct.unpack_from("<I", self.imem, pc - IMEM_BASE)[0]

    # -- CSRs --------------------------------------------------------------------------
    def csr_read(self, a):
        if a in (0xB00, 0xC00):
            return self.cycle & M32
        if a in (0xB80, 0xC80):
            return self.cycle >> 32
        if a in (0xB02, 0xC02):
            return self.instret & M32
        if a in (0xB82, 0xC82):
            return self.instret >> 32
        if a == 0x301:
            return 0x4000_1100
        if a == 0x344:
            return 0x80 if self.cycle >= self.mtimecmp else 0
        if a in (0xF11, 0xF12, 0xF13, 0xF14):
            return 0
        if (a >> 4) in (0xB0, 0xC0) and 3 <= (a & 0xF) <= 8:
            return 0
        if a in self.csr:
            return self.csr[a]
        raise Trap(2)

    def csr_write(self, a, v):
        v &= M32
        if (a >> 10) == 3:
            raise Trap(2)
        if a == 0x300:
            self.csr[a] = 0x1800 | (v & 0x88)
        elif a == 0x304:
            self.csr[a] = v & 0x888
        elif a in (0x305, 0x341):
            self.csr[a] = v & ~3
        elif a == 0x342:
            self.csr[a] = v & 0x8000_000F
        elif a in (0xB00, 0xB80, 0xB02, 0xB82):
            pass                                  # counters: not modelled as writable
        elif a in self.csr:
            self.csr[a] = v

    # -- execution ---------------------------------------------------------------------
    def wr(self, rd, v, rec):
        if rd:
            self.x[rd] = v & M32
            rec["rd"], rec["rd_val"] = rd, v & M32

    def step(self):
        """Execute one instruction. Returns a retire record, or None on a trap."""
        pc = self.pc
        rec = {"pc": pc, "insn": 0, "rd": 0, "rd_val": 0, "mem_addr": 0, "wmask": 0, "wdata": 0}
        try:
            insn = self.fetch(pc)
            rec["insn"] = insn
            npc = self.execute(pc, insn, rec)
            if npc & 3:
                raise Trap(0, npc)
        except Trap as t:
            self.trap(pc, t.cause, t.tval if t.cause != 2 else rec["insn"])
            self.cycle += 1
            return None
        self.pc = npc & M32
        self.cycle += 1
        self.instret += 1
        return rec

    def trap(self, pc, cause, tval):
        st = self.csr[0x300]
        mie = (st >> 3) & 1
        self.csr[0x300] = (st & ~0x88) | (mie << 7)
        self.csr[0x341] = pc
        self.csr[0x342] = cause
        self.csr[0x343] = tval & M32
        self.pc = self.csr[0x305]

    def execute(self, pc, insn, rec):
        x = self.x
        opc = insn & 0x7F
        rd = (insn >> 7) & 31
        f3 = (insn >> 12) & 7
        rs1, rs2 = (insn >> 15) & 31, (insn >> 20) & 31
        f7 = insn >> 25
        a, b = x[rs1], x[rs2]
        imm_i = sext(insn >> 20, 12)
        npc = pc + 4

        if opc == 0x37:                                           # LUI
            self.wr(rd, insn & 0xFFFFF000, rec)
        elif opc == 0x17:                                         # AUIPC
            self.wr(rd, pc + (insn & 0xFFFFF000), rec)
        elif opc == 0x6F:                                         # JAL
            imm = sext(((insn >> 31) << 20) | (((insn >> 12) & 0xFF) << 12) |
                       (((insn >> 20) & 1) << 11) | (((insn >> 21) & 0x3FF) << 1), 21)
            t = (pc + imm) & M32
            if t & 3:
                raise Trap(0, t)
            self.wr(rd, pc + 4, rec)
            npc = t
        elif opc == 0x67 and f3 == 0:                             # JALR
            t = (a + imm_i) & M32 & ~1
            if t & 3:
                raise Trap(0, t)
            self.wr(rd, pc + 4, rec)
            npc = t
        elif opc == 0x63 and f3 not in (2, 3):                    # branches
            imm = sext(((insn >> 31) << 12) | (((insn >> 7) & 1) << 11) |
                       (((insn >> 25) & 0x3F) << 5) | (((insn >> 8) & 0xF) << 1), 13)
            taken = {0: a == b, 1: a != b, 4: s32(a) < s32(b), 5: s32(a) >= s32(b),
                     6: a < b, 7: a >= b}[f3]
            if taken:
                t = (pc + imm) & M32
                if t & 3:
                    raise Trap(0, t)
                npc = t
        elif opc == 0x03 and f3 in (0, 1, 2, 4, 5):               # loads
            addr = (a + imm_i) & M32
            size = 1 << (f3 & 3)
            if addr & (size - 1):
                raise Trap(4, addr)
            v = self.load(addr, size)
            if f3 == 0:
                v = sext(v, 8)
            elif f3 == 1:
                v = sext(v, 16)
            rec["mem_addr"] = addr
            self.wr(rd, v, rec)
        elif opc == 0x23 and f3 <= 2:                             # stores
            imm = sext(((insn >> 25) << 5) | ((insn >> 7) & 31), 12)
            addr = (a + imm) & M32
            size = 1 << f3
            if addr & (size - 1):
                raise Trap(6, addr)
            self.store(addr, size, b)
            rec["mem_addr"] = addr
            rec["wmask"] = ((1 << size) - 1) << (addr & 3)
            rec["wdata"] = ((b & ((1 << (8 * size)) - 1)) * {1: 0x01010101, 2: 0x00010001, 4: 1}[size]) & M32
        elif opc == 0x13:                                         # OP-IMM
            if f3 == 1:
                if f7:
                    raise Trap(2)
                self.wr(rd, alu("sll", a, rs2), rec)
            elif f3 == 5:
                if f7 not in (0, 0x20):
                    raise Trap(2)
                self.wr(rd, alu("sra" if f7 else "srl", a, rs2), rec)
            else:
                self.wr(rd, alu(self.ALU_F3[f3], a, imm_i), rec)
        elif opc == 0x33:                                         # OP
            if f7 == 0:
                self.wr(rd, alu(self.ALU_F3[f3], a, b), rec)
            elif f7 == 0x20 and f3 in (0, 5):
                self.wr(rd, alu("sub" if f3 == 0 else "sra", a, b), rec)
            else:
                raise Trap(2)
        elif opc == 0x0F and f3 in (0, 1):                        # FENCE / FENCE.I
            pass
        elif opc == 0x73:
            if f3 == 0:
                if insn == 0x00000073:
                    raise Trap(11)
                if insn == 0x00100073:
                    raise Trap(3, pc)
                if insn == 0x30200073:                            # MRET
                    st = self.csr[0x300]
                    self.csr[0x300] = (st & ~0x8) | ((st >> 4) & 0x8) | 0x80
                    npc = self.csr[0x341]
                elif insn != 0x10500073:                          # WFI = NOP
                    raise Trap(2)
            elif f3 == 4:
                raise Trap(2)
            else:
                addr = insn >> 20
                src = rs1 if f3 & 4 else a
                writes = (f3 & 3) == 1 or rs1 != 0
                old = self.csr_read(addr)
                if writes:
                    new = {1: src, 2: old | src, 3: old & ~src}[f3 & 3]
                    self.csr_write(addr, new)
                self.wr(rd, old, rec)
        else:
            raise Trap(2)
        return npc

    def run(self, max_steps=50_000_000, trace=None):
        for _ in range(max_steps):
            rec = self.step()
            if rec and trace:
                trace.write(f"{rec['pc']:08x} {rec['insn']:08x} {rec['rd']:02d} {rec['rd_val']:08x} "
                            f"{rec['mem_addr']:08x} {rec['wmask']:x} {rec['wdata']:08x}\n")
            if self.tohost is not None:
                return self.tohost
        return None
