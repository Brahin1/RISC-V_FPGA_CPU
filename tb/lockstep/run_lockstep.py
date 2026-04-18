#!/usr/bin/env python3
"""run_lockstep.py - run programs on the core and on Spike, compare every
retired instruction.

  run_lockstep.py --elf a.elf b.elf ...          existing programs
  run_lockstep.py --random 200 --seed 1000       random programs (rand_gen.py)
  run_lockstep.py --ref iss ...                  use tb/iss/rv32iss.py instead of Spike

The core must have been built in tb/verilator. Spike is taken from $SPIKE or
PATH. Work files go to tb/lockstep/work/ (kept for failing cases only).
"""

import argparse
import multiprocessing as mp
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import compare  # noqa: E402

SPIKE = os.environ.get("SPIKE", "spike")
SPIKE_ARGS = ["--disable-dtb", "--no-dm", "--priv=m", "--isa=rv32im_zicsr",
              "-m0x0:0x8000,0x10000:0x8000,0x10000000:0x1000", "--log-commits"]
CC = os.environ.get("CROSS", "riscv64-unknown-elf-") + "gcc"
CFLAGS = ["-march=rv32im_zicsr", "-mabi=ilp32", "-static", "-nostdlib", "-nostartfiles",
          "-T", os.path.join(ROOT, "tests", "env", "link.ld")]
WORK = os.path.join(HERE, "work")


def sim_exe(bp_mode):
    return os.path.join(ROOT, "tb", "verilator", f"obj_dir_bp{bp_mode}", "Vsoc_top")


def run_one(job):
    """job = (name, elf_or_None, seed_or_None, bp_mode, max_cycles, ref) -> (name, n, err)"""
    name, elf, seed, bp_mode, max_cycles, ref = job
    wd = os.path.join(WORK, name)
    os.makedirs(wd, exist_ok=True)
    try:
        if seed is not None:
            src = os.path.join(wd, "prog.S")
            subprocess.run([sys.executable, os.path.join(HERE, "rand_gen.py"),
                            "--seed", str(seed), "-o", src], check=True)
            elf = os.path.join(wd, "prog.elf")
            subprocess.run([CC, *CFLAGS, src, "-o", elf], check=True, capture_output=True)
        stem = os.path.join(wd, "prog")
        subprocess.run([sys.executable, os.path.join(ROOT, "tools", "elf2hex.py"), elf,
                        "--out", stem], check=True)

        trace = os.path.join(wd, "dut.trace")
        r = subprocess.run([sim_exe(bp_mode), f"+imem={stem}.imem.hex", f"+dmem={stem}.dmem.hex",
                            f"+trace={trace}", "+quiet", f"+max_cycles={max_cycles}"],
                           capture_output=True, text=True)
        if r.returncode != 0:
            return name, 0, "DUT did not pass: " + r.stderr.strip()

        if ref == "iss":
            log = os.path.join(wd, "iss.trace")
            r = subprocess.run([sys.executable, os.path.join(ROOT, "tb", "iss", "rv32iss.py"),
                                elf, "--trace", log], capture_output=True)
            if r.returncode != 0:
                return name, 0, f"ISS exited with {r.returncode}"
            ref_recs = compare.parse_dut(log)
        else:
            log = os.path.join(wd, "spike.log")
            with open(log, "w") as f:
                r = subprocess.run([SPIKE, *SPIKE_ARGS, elf], stderr=f, stdout=subprocess.DEVNULL)
            if r.returncode != 0:
                return name, 0, f"spike exited with {r.returncode}"
            ref_recs = compare.parse_spike(log)

        n, err = compare.compare(compare.parse_dut(trace), ref_recs)
        if err is None:
            shutil.rmtree(wd, ignore_errors=True)
        return name, n, err
    except subprocess.CalledProcessError as e:
        return name, 0, f"build step failed: {e}"


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--elf", nargs="*", default=[])
    ap.add_argument("--random", type=int, default=0, help="number of random programs")
    ap.add_argument("--seed", type=int, default=1, help="first random seed")
    ap.add_argument("--bp-mode", type=int, default=1)
    ap.add_argument("--ref", choices=["spike", "iss"], default="spike")
    ap.add_argument("--max-cycles", type=int, default=200_000_000)
    ap.add_argument("-j", "--jobs", type=int, default=os.cpu_count())
    args = ap.parse_args()

    jobs = []
    for e in args.elf:
        jobs.append((os.path.basename(e).removesuffix(".elf"), os.path.abspath(e), None,
                     args.bp_mode, args.max_cycles, args.ref))
    for s in range(args.seed, args.seed + args.random):
        jobs.append((f"rand_{s}", None, s, args.bp_mode, args.max_cycles, args.ref))
    if not jobs:
        ap.error("nothing to run")

    t0 = time.time()
    total, fails = 0, []
    with mp.Pool(args.jobs) as pool:
        for name, n, err in pool.imap_unordered(run_one, jobs):
            total += n
            if err:
                fails.append(name)
                print(f"FAIL {name}\n{err}\n")
            elif len(jobs) <= 64:
                print(f"  ok   {name:<28} {n:>10} instructions")

    dt = time.time() - t0
    print(f"\nlockstep: {len(jobs) - len(fails)}/{len(jobs)} programs, "
          f"{total:,} instructions compared, {len(fails)} divergent  ({dt:.0f} s)")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
