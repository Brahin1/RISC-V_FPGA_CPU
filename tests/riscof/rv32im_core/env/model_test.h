// model_test.h - RVMODEL macros for the RV32IM TCM core (riscv-arch-test)
#ifndef _COMPLIANCE_MODEL_H
#define _COMPLIANCE_MODEL_H

#define TOHOST_ADDR 0x10000000

#define RVMODEL_DATA_SECTION \
        .align 8; .global begin_regstate; begin_regstate: \
        .word 128; \
        .align 8; .global end_regstate; end_regstate: \
        .word 4;

#define RVMODEL_HALT \
        fence; \
        li x1, 1; \
        li t5, TOHOST_ADDR; \
  write_tohost: \
        sw x1, 0(t5); \
        j write_tohost;

#define RVMODEL_BOOT

#define RVMODEL_DATA_BEGIN \
        RVMODEL_DATA_SECTION \
        .align 4; .global begin_signature; begin_signature:

#define RVMODEL_DATA_END \
        .align 4; .global end_signature; end_signature:

#define RVMODEL_IO_INIT
#define RVMODEL_IO_WRITE_STR(_R, _STR)
#define RVMODEL_IO_CHECK()
#define RVMODEL_IO_ASSERT_GPR_EQ(_S, _R, _I)
#define RVMODEL_IO_ASSERT_SFPR_EQ(_F, _R, _I)
#define RVMODEL_IO_ASSERT_DFPR_EQ(_D, _R, _I)

// no software / external interrupt sources on this SoC
#define RVMODEL_SET_MSW_INT
#define RVMODEL_CLEAR_MSW_INT
#define RVMODEL_CLEAR_MTIMER_INT
#define RVMODEL_CLEAR_MEXT_INT

#endif
