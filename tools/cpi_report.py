#!/usr/bin/env python3
"""cpi_report.py - turn the PERF line printed by a program into a CPI breakdown.

The PERF line comes from print_perf_counters() (sw/common/console.c) or the
CoreMark port and looks like:

  PERF cycles=.. instret=.. load_use=.. br_mispredict=.. jmp_redirect=..
       muldiv_stall=.. branches=.. traps=..

Penalties assumed by the breakdown (see rtl/core_top.sv):
  load-use interlock       1 cycle each (counter already counts cycles)
  branch mispredict        1 cycle  (resolved in EX, squashes ID)
  JAL/JALR redirect        1 cycle
  mul-use / divider stall  counter already counts cycles
Anything left over (trap flushes, pipeline fill) is reported as "other".
"""

import re
import sys


def parse(text):
    m = None
    for line in text.splitlines():
        if line.startswith("PERF "):
            m = line
    if m is None:
        sys.exit("no PERF line found")
    return {k: int(v) for k, v in re.findall(r"(\w+)=(\d+)", m)}


def report(p):
    cyc, ins = p["cycles"], p["instret"]
    parts = [
        ("base (1 instr/cycle)", ins),
        ("branch mispredicts", p["br_mispredict"]),
        ("jump redirects", p["jmp_redirect"]),
        ("load-use interlocks", p["load_use"]),
        ("mul/div stalls", p["muldiv_stall"]),
    ]
    other = cyc - sum(c for _, c in parts)
    parts.append(("other (traps, fill)", other))

    lines = [f"{'component':<24}{'cycles':>12}{'CPI':>9}", "-" * 45]
    for name, c in parts:
        lines.append(f"{name:<24}{c:>12}{c / ins:>9.3f}")
    lines.append("-" * 45)
    lines.append(f"{'total':<24}{cyc:>12}{cyc / ins:>9.3f}")
    if p.get("branches"):
        acc = 100.0 * (1 - p["br_mispredict"] / p["branches"])
        lines.append(f"\nconditional branches: {p['branches']}  "
                     f"prediction accuracy: {acc:.1f}%")
    return "\n".join(lines)


def main():
    text = open(sys.argv[1]).read() if len(sys.argv) > 1 else sys.stdin.read()
    print(report(parse(text)))


if __name__ == "__main__":
    main()
