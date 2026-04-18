#!/usr/bin/env python3
"""compare.py - instruction-by-instruction comparison of the core's retire trace
against a Spike commit log (spike --log-commits).

Per retired instruction it checks:
  * PC and instruction word
  * destination register and written value
  * load address, store address and store data

Reads of counters that cannot match a functional model (mcycle, mhpmcounter*,
...) are compared on PC/instruction only.

Trace format written by tb/verilator/sim_main.cpp (+trace=):
  <pc> <insn> <rd> <rd_wdata> <mem_addr> <wmask> <wdata>
"""

import re
import sys
from dataclasses import dataclass

SPIKE_RE = re.compile(r"^core\s+\d+:\s+\d\s+0x([0-9a-f]+)\s+\(0x([0-9a-f]+)\)(.*)$")
XREG_RE = re.compile(r"\bx(\d+)\s+0x([0-9a-f]+)")
MEM_RE = re.compile(r"\bmem\s+0x([0-9a-f]+)(?:\s+0x([0-9a-f]+))?")

# CSRs whose value legitimately differs between the core and Spike
NONDET_CSRS = {0xB00, 0xB80, 0xC00, 0xC80, 0xC01, 0xC81} | \
              set(range(0xB03, 0xB20)) | set(range(0xB83, 0xBA0)) | \
              set(range(0xC03, 0xC20)) | set(range(0xC83, 0xCA0))


@dataclass
class Rec:
    pc: int
    insn: int
    rd: int = 0
    rd_val: int = 0
    mem_addr: int | None = None
    store_val: int | None = None
    store_bytes: int = 0


def is_nondet_csr_read(insn):
    return (insn & 0x7F) == 0x73 and ((insn >> 12) & 0x3) != 0 and (insn >> 20) in NONDET_CSRS


def parse_spike(path, start_pc=0):
    recs = []
    started = False
    with open(path) as f:
        for line in f:
            m = SPIKE_RE.match(line)
            if not m:
                continue
            pc, insn, rest = int(m.group(1), 16), int(m.group(2), 16), m.group(3)
            if not started:
                if pc != start_pc:
                    continue
                started = True
            r = Rec(pc & 0xFFFFFFFF, insn)
            for xm in XREG_RE.finditer(rest):
                rd = int(xm.group(1))
                if rd != 0:
                    r.rd, r.rd_val = rd, int(xm.group(2), 16) & 0xFFFFFFFF
            mm = MEM_RE.search(rest)
            if mm:
                r.mem_addr = int(mm.group(1), 16) & 0xFFFFFFFF
                if mm.group(2) is not None:
                    r.store_val = int(mm.group(2), 16)
                    r.store_bytes = len(mm.group(2)) // 2
            recs.append(r)
    return recs


def parse_dut(path):
    recs = []
    with open(path) as f:
        for line in f:
            p = line.split()
            if len(p) != 7:
                continue
            pc, insn, rd, rdv, maddr, wmask, wdata = (int(p[0], 16), int(p[1], 16), int(p[2]),
                                                      int(p[3], 16), int(p[4], 16), int(p[5], 16),
                                                      int(p[6], 16))
            r = Rec(pc, insn, rd, rdv)
            opc = insn & 0x7F
            if opc in (0x03, 0x23):            # load / store
                r.mem_addr = maddr
            if wmask:
                lsb = (wmask & -wmask).bit_length() - 1
                nbytes = bin(wmask).count("1")
                r.store_bytes = nbytes
                r.store_val = (wdata >> (8 * lsb)) & ((1 << (8 * nbytes)) - 1)
            recs.append(r)
    return recs


def fmt(r):
    s = f"pc=0x{r.pc:08x} insn=0x{r.insn:08x}"
    if r.rd:
        s += f" x{r.rd}=0x{r.rd_val:08x}"
    if r.mem_addr is not None:
        s += f" mem=0x{r.mem_addr:08x}"
    if r.store_val is not None:
        s += f" st=0x{r.store_val:0{2 * r.store_bytes}x}"
    return s


def compare(dut, ref, max_tail=4):
    """Return (n_compared, error_message_or_None)."""
    if len(ref) < len(dut):
        return 0, f"reference log shorter than DUT trace ({len(ref)} < {len(dut)})"
    for i, (d, s) in enumerate(zip(dut, ref)):
        problems = []
        if d.pc != s.pc or d.insn != s.insn:
            problems.append("pc/insn")
        else:
            nondet = is_nondet_csr_read(d.insn)
            if d.rd != s.rd or (not nondet and d.rd_val != s.rd_val):
                problems.append("rd")
            if (d.mem_addr is not None or s.mem_addr is not None) and d.mem_addr != s.mem_addr:
                problems.append("mem addr")
            if d.store_val != s.store_val:
                problems.append("store data")
        if problems:
            ctx = "\n".join(f"      [{j}] {fmt(dut[j])}" for j in range(max(0, i - 4), i))
            return i, (f"divergence at retired instruction {i} ({', '.join(problems)})\n"
                       f"  previous:\n{ctx}\n"
                       f"  dut : {fmt(d)}\n"
                       f"  ref : {fmt(s)}")
    return len(dut), None


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: compare.py <dut.trace> <spike.log>")
    dut = parse_dut(sys.argv[1])
    ref = parse_spike(sys.argv[2])
    n, err = compare(dut, ref)
    if err:
        print(err)
        sys.exit(1)
    print(f"OK: {n} instructions match")


if __name__ == "__main__":
    main()
