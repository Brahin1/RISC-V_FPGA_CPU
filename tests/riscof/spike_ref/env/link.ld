/* riscv-arch-test layout for the RV32IM core.
 * The branch/JAL tests contain ~1.7 MB of code, so compliance runs use the
 * large-memory simulation build (tb/verilator: make riscof):
 *   IMEM 2 MB at 0x0000_0000, DMEM 64 KB at 0x0040_0000. */
OUTPUT_ARCH("riscv")
ENTRY(rvtest_entry_point)

MEMORY
{
  IMEM (rx) : ORIGIN = 0x00000000, LENGTH = 2M
  DMEM (rw) : ORIGIN = 0x00400000, LENGTH = 64K
}

SECTIONS
{
  .text : { *(.text.init) *(.text .text.*) } > IMEM
  .data : { *(.data .data.*) *(.data.string) *(.sdata .sdata.*) } > DMEM
  .bss  : { *(.bss .bss.*) *(.sbss .sbss.*) } > DMEM
  _end = .;

  tohost   = 0x10000000;
  fromhost = 0x10000040;
}
