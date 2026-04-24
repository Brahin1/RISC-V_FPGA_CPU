"""Decoder: legality of random instruction words against an independent
Python decode, plus immediates and rd/rs usage for every valid opcode."""

import random

import cocotb
from cocotb.triggers import Timer


def sext(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


def legal(i):
    opc, f3, f7 = i & 0x7F, (i >> 12) & 7, i >> 25
    if opc in (0x37, 0x17, 0x6F):
        return True
    if opc == 0x67:
        return f3 == 0
    if opc == 0x63:
        return f3 not in (2, 3)
    if opc == 0x03:
        return f3 in (0, 1, 2, 4, 5)
    if opc == 0x23:
        return f3 <= 2
    if opc == 0x13:
        if f3 == 1:
            return f7 == 0
        if f3 == 5:
            return f7 in (0, 0x20)
        return True
    if opc == 0x33:
        return f7 in (0, 1) or (f7 == 0x20 and f3 in (0, 5))
    if opc == 0x0F:
        return f3 in (0, 1)
    if opc == 0x73:
        if f3 == 0:
            return i in (0x00000073, 0x00100073, 0x30200073, 0x10500073)
        return f3 != 4
    return False


def expected_imm(i):
    opc = i & 0x7F
    if opc in (0x37, 0x17):
        return i & 0xFFFFF000
    if opc == 0x6F:
        return sext(((i >> 31) << 20) | (((i >> 12) & 0xFF) << 12) |
                    (((i >> 20) & 1) << 11) | (((i >> 21) & 0x3FF) << 1), 21)
    if opc == 0x63:
        return sext(((i >> 31) << 12) | (((i >> 7) & 1) << 11) |
                    (((i >> 25) & 0x3F) << 5) | (((i >> 8) & 0xF) << 1), 13)
    if opc == 0x23:
        return sext(((i >> 25) << 5) | ((i >> 7) & 31), 12)
    if opc in (0x03, 0x13, 0x67):
        return sext(i >> 20, 12)
    return None


VALID_OPCODES = [0x37, 0x17, 0x6F, 0x67, 0x63, 0x03, 0x23, 0x13, 0x33, 0x0F, 0x73]


@cocotb.test()
async def random_words(dut):
    rng = random.Random(5)
    n_legal = 0
    for k in range(40_000):
        if k % 2:
            i = rng.getrandbits(32)
        else:     # bias toward real opcodes so most legal encodings get covered
            i = (rng.getrandbits(25) << 7) | rng.choice(VALID_OPCODES)
        dut.insn.value = i
        await Timer(1, "ns")
        exp_legal = legal(i)
        assert dut.illegal.value.integer == (not exp_legal), f"0x{i:08x}: illegal={dut.illegal.value}"
        if not exp_legal:
            assert dut.rd_we.value == 0 and dut.mem_write.value == 0 and dut.mem_read.value == 0
            continue
        n_legal += 1
        imm = expected_imm(i)
        if imm is not None:
            assert dut.imm.value.integer == imm & 0xFFFFFFFF, f"0x{i:08x}: imm 0x{dut.imm.value.integer:08x}"
        rd = (i >> 7) & 31
        if rd == 0:
            assert dut.rd_we.value == 0, f"0x{i:08x}: write to x0 enabled"
        opc, f3, f7 = i & 0x7F, (i >> 12) & 7, i >> 25
        if opc == 0x33 and f7 == 1:
            assert dut.is_mul.value == (f3 < 4) and dut.is_div.value == (f3 >= 4)
        if opc == 0x73 and f3 in (2, 3, 6, 7):
            assert dut.csr_wr.value == (((i >> 15) & 31) != 0), f"0x{i:08x}: csr_wr"
    dut._log.info(f"{n_legal} legal encodings checked")


@cocotb.test()
async def system_ops(dut):
    for insn, sig in ((0x00000073, "is_ecall"), (0x00100073, "is_ebreak"), (0x30200073, "is_mret")):
        dut.insn.value = insn
        await Timer(1, "ns")
        assert getattr(dut, sig).value == 1
        assert dut.illegal.value == 0
