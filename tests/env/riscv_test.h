// riscv_test.h - riscv-tests environment for the RV32IM TCM core
//
// Replaces env/p from riscv-tests:
//   * code at 0x0000_0000 (IMEM), data at 0x0001_0000 (DMEM)
//   * pass/fail written straight to the tohost MMIO register (0x1000_0000)
//     instead of going through ECALL + an HTIF handler
//   * machine mode only, no satp/pmp/delegation setup
// Any unexpected trap is reported as a failure with code 0x400 | mcause.

#ifndef _ENV_RV32_TCM_H
#define _ENV_RV32_TCM_H

#include "../riscv-tests/env/encoding.h"

#define TOHOST_ADDR 0x10000000

#define RVTEST_RV32U .macro init; .endm
#define RVTEST_RV64U RVTEST_RV32U
#define RVTEST_RV32M RVTEST_RV32U
#define RVTEST_RV64M RVTEST_RV32U

#define TESTNUM gp

#define INIT_XREG                                                       \
  li x1, 0;  li x2, 0;  li x3, 0;  li x4, 0;  li x5, 0;  li x6, 0;      \
  li x7, 0;  li x8, 0;  li x9, 0;  li x10, 0; li x11, 0; li x12, 0;     \
  li x13, 0; li x14, 0; li x15, 0; li x16, 0; li x17, 0; li x18, 0;     \
  li x19, 0; li x20, 0; li x21, 0; li x22, 0; li x23, 0; li x24, 0;     \
  li x25, 0; li x26, 0; li x27, 0; li x28, 0; li x29, 0; li x30, 0;     \
  li x31, 0;

#define RVTEST_CODE_BEGIN                                               \
        .section .text.init;                                            \
        .align  6;                                                      \
        .globl _start;                                                  \
_start:                                                                 \
        INIT_XREG;                                                      \
        la t0, trap_vector;                                             \
        csrw mtvec, t0;                                                 \
        j test_start;                                                   \
        .align 2;                                                       \
trap_vector:                                                            \
        csrr TESTNUM, mcause;                                           \
        ori TESTNUM, TESTNUM, 0x400;                                    \
        j write_tohost_fail;                                            \
test_start:                                                             \
        init;

#define RVTEST_CODE_END                                                 \
write_tohost_fail:                                                      \
        sll TESTNUM, TESTNUM, 1;                                        \
        or TESTNUM, TESTNUM, 1;                                         \
        li t5, TOHOST_ADDR;                                             \
        sw TESTNUM, 0(t5);                                              \
1:      j 1b;                                                           \
        unimp

#define RVTEST_PASS                                                     \
        fence;                                                          \
        li TESTNUM, 1;                                                  \
        li t5, TOHOST_ADDR;                                             \
        sw TESTNUM, 0(t5);                                              \
1:      j 1b;

#define RVTEST_FAIL                                                     \
        fence;                                                          \
1:      beqz TESTNUM, 1b;                                               \
        j write_tohost_fail;

#define EXTRA_DATA

#define RVTEST_DATA_BEGIN                                               \
        EXTRA_DATA                                                      \
        .align 4; .global begin_signature; begin_signature:

#define RVTEST_DATA_END .align 4; .global end_signature; end_signature:

#endif
