/* link.ld - riscv-tests layout for the RV32IM TCM core */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  IMEM (rx) : ORIGIN = 0x00000000, LENGTH = 32K
  DMEM (rw) : ORIGIN = 0x00010000, LENGTH = 32K
}

SECTIONS
{
  .text : { *(.text.init) *(.text .text.*) } > IMEM
  .data : { *(.rodata .rodata.*) *(.data .data.*) *(.sdata .sdata.*) } > DMEM
  .bss  : { *(.sbss .sbss.*) *(.bss .bss.*) } > DMEM
  _end = .;

  tohost   = 0x10000000;
  fromhost = 0x10000040;
}
