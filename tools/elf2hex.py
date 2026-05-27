#!/usr/bin/env python3
"""elf2hex.py - split an RV32 ELF into IMEM / DMEM images.

Writes, for an output prefix P:
  P.imem.hex  P.dmem.hex   $readmemh files (one 32-bit word per line, word 0 = base)
  P.imem.bin  P.dmem.bin   raw little-endian images for the PS loader

Every PT_LOAD segment is placed by physical address into whichever memory
contains it. Anything outside IMEM/DMEM is an error (except NOBITS-only space).
"""

import argparse
import struct
import sys

IMEM_BASE, IMEM_SIZE = 0x0000_0000, 32 * 1024
DMEM_BASE, DMEM_SIZE = 0x0001_0000, 32 * 1024     # defaults; see --imem-size etc.

PT_LOAD = 1


def read_segments(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"\x7fELF":
        sys.exit(f"{path}: not an ELF file")
    if data[4] != 1 or data[5] != 1:
        sys.exit(f"{path}: expected ELF32 little-endian")

    (e_entry, e_phoff, _e_shoff, _flags, _ehsize, e_phentsize, e_phnum) = struct.unpack_from(
        "<IIIIHHH", data, 0x18)

    segs = []
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type, p_offset, _vaddr, p_paddr, p_filesz, _memsz, _flags, _align = struct.unpack_from(
            "<IIIIIIII", data, off)
        if p_type == PT_LOAD and p_filesz:
            segs.append((p_paddr, data[p_offset:p_offset + p_filesz]))
    return e_entry, segs


def place(segs, base, size):
    img = bytearray(size)
    used = 0
    for addr, blob in segs:
        if base <= addr < base + size:
            end = addr + len(blob)
            if end > base + size:
                sys.exit(f"segment at 0x{addr:08x} overflows memory at 0x{base:08x}")
            img[addr - base:end - base] = blob
            used = max(used, end - base)
    return img, used


def write_hex(path, img, used):
    nwords = (used + 3) // 4
    with open(path, "w") as f:
        for w in range(nwords):
            f.write(f"{struct.unpack_from('<I', img, 4 * w)[0]:08x}\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("elf")
    ap.add_argument("--out", required=True, help="output prefix")
    ap.add_argument("--imem-size", type=lambda s: int(s, 0), default=IMEM_SIZE)
    ap.add_argument("--dmem-base", type=lambda s: int(s, 0), default=DMEM_BASE)
    ap.add_argument("--dmem-size", type=lambda s: int(s, 0), default=DMEM_SIZE)
    args = ap.parse_args()
    imem_size, dmem_base, dmem_size = args.imem_size, args.dmem_base, args.dmem_size

    entry, segs = read_segments(args.elf)
    for addr, blob in segs:
        in_i = IMEM_BASE <= addr < IMEM_BASE + imem_size
        in_d = dmem_base <= addr < dmem_base + dmem_size
        if not (in_i or in_d):
            sys.exit(f"segment at 0x{addr:08x} ({len(blob)} B) is outside IMEM/DMEM")

    imem, iused = place(segs, IMEM_BASE, imem_size)
    dmem, dused = place(segs, dmem_base, dmem_size)

    write_hex(args.out + ".imem.hex", imem, iused)
    write_hex(args.out + ".dmem.hex", dmem, dused)
    with open(args.out + ".imem.bin", "wb") as f:
        f.write(imem[:(iused + 3) & ~3])
    with open(args.out + ".dmem.bin", "wb") as f:
        f.write(dmem[:(dused + 3) & ~3])

    if entry != IMEM_BASE:
        print(f"warning: entry point 0x{entry:08x} != reset vector 0x{IMEM_BASE:08x}",
              file=sys.stderr)


if __name__ == "__main__":
    main()
