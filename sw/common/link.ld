/* link.ld - memory layout for the RV32IM core
 *
 * Harvard TCMs: code lives in IMEM, everything the program loads or stores
 * (including .rodata) lives in DMEM. The core cannot read IMEM with loads.
 */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 32K
  DMEM (rw)  : ORIGIN = 0x00010000, LENGTH = 32K
}

STACK_SIZE = 4K;

SECTIONS
{
  .text : {
    *(.text.init)
    *(.text .text.*)
  } > IMEM

  .rodata : ALIGN(4) {
    *(.rodata .rodata.*)
    *(.srodata .srodata.*)
  } > DMEM

  .data : ALIGN(4) {
    *(.data .data.*)
    . = ALIGN(4);
    __global_pointer$ = . + 0x800;
    *(.sdata .sdata.*)
  } > DMEM

  .bss (NOLOAD) : ALIGN(4) {
    __bss_start = .;
    *(.sbss .sbss.*)
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > DMEM

  .stack (NOLOAD) : ALIGN(16) {
    . += STACK_SIZE;
    __stack_top = .;
  } > DMEM

  /* MMIO (see rtl/mmio.sv). tohost/fromhost also let Spike's HTIF see
     the pass/fail write when running the same ELF on the reference model. */
  tohost   = 0x10000000;
  fromhost = 0x10000040;
  CONSOLE  = 0x10000004;
  MTIME    = 0x10000008;
  MTIMECMP = 0x10000010;
  LED      = 0x10000018;
}
