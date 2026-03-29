#!/usr/bin/env python3
"""run_tests.py - run a list of test ELFs on one of the simulators.

  --sim five-stage    Verilator model of soc_top (tb/verilator)
  --sim single-cycle  Verilator model of the single-cycle reference (tb/sc)
  --sim spike         Spike reference model

Each ELF must have <name>.imem.hex / <name>.dmem.hex next to it (tools/elf2hex.py).
Prints one line per test and a summary; exit status is non-zero on any failure.
"""

import argparse
import os
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

SPIKE = os.environ.get("SPIKE", "spike")
SPIKE_ARGS = ["--disable-dtb", "--no-dm", "--priv=m", "--isa=rv32im_zicsr",
              "-m0x0:0x8000,0x10000:0x8000,0x10000000:0x1000"]


def sim_cmd(sim, elf, bp_mode):
    stem = elf[:-4] if elf.endswith(".elf") else elf
    if sim == "five-stage":
        exe = os.path.join(ROOT, "tb", "verilator", f"obj_dir_bp{bp_mode}", "Vsoc_top")
        return [exe, f"+imem={stem}.imem.hex", f"+dmem={stem}.dmem.hex", "+quiet",
                "+max_cycles=2000000"]
    if sim == "single-cycle":
        exe = os.path.join(ROOT, "tb", "sc", "obj_dir", "Vsc_tb")
        return [exe, f"+imem={stem}.imem.hex", f"+dmem={stem}.dmem.hex"]
    if sim == "spike":
        return [SPIKE, *SPIKE_ARGS, elf]
    raise ValueError(sim)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sim", choices=["five-stage", "single-cycle", "spike"], default="five-stage")
    ap.add_argument("--bp-mode", type=int, default=1)
    ap.add_argument("elfs", nargs="+")
    args = ap.parse_args()

    failed = []
    t0 = time.time()
    for elf in args.elfs:
        name = os.path.basename(elf).removesuffix(".elf")
        try:
            r = subprocess.run(sim_cmd(args.sim, elf, args.bp_mode), capture_output=True,
                               text=True, timeout=120)
            ok = r.returncode == 0
            detail = (r.stderr.strip().splitlines() or [""])[-1]
        except subprocess.TimeoutExpired:
            ok, detail = False, "host timeout"
        print(f"  {'PASS' if ok else 'FAIL'}  {name:<24} {detail}")
        if not ok:
            failed.append(name)

    n = len(args.elfs)
    print(f"\n{args.sim}: {n - len(failed)}/{n} passed  ({time.time() - t0:.1f} s)")
    if failed:
        print("failed: " + " ".join(failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
