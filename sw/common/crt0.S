# crt0.S - startup for bare-metal programs on the RV32IM core
#
#   * set up gp/sp, install a trap handler, clear .bss
#   * call main()
#   * report main's return value through tohost:
#       0  -> write 1           (pass)
#       n  -> write (n<<1) | 1  (fail, code n)

    .section .text.init
    .globl _start
_start:
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop
    la      sp, __stack_top

    la      t0, trap_entry
    csrw    mtvec, t0

    la      t0, __bss_start
    la      t1, __bss_end
1:  bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:
    call    main

    .globl  _exit
_exit:
    beqz    a0, 3f
    slli    a0, a0, 1
    ori     a0, a0, 1
    j       4f
3:  li      a0, 1
4:  li      t0, 0x10000000
    fence
    sw      a0, 0(t0)
5:  j       5b

# Default trap handler: report mcause as the failure code.
# Programs that use interrupts provide their own strong trap_entry.
    .weak   trap_entry
    .align  2
trap_entry:
    csrr    a0, mcause
    addi    a0, a0, 0x100
    j       _exit
