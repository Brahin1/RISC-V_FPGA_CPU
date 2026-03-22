"""ALU against the ISS reference: every op, corner operands plus random vectors."""

import random

import cocotb
from cocotb.triggers import Timer

from rv32iss import alu as ref_alu

# must match alu_op_e in core_pkg.sv
OPS = ["add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"]
CORNERS = [0, 1, 2, 0x7FFFFFFF, 0x80000000, 0x80000001, 0xFFFFFFFF, 0xFFFFFFFE,
           31, 32, 33, 0x55555555, 0xAAAAAAAA, 0x0000FFFF, 0xFFFF0000]
N_RANDOM = 10_000


async def check(dut, op_idx, a, b):
    dut.op.value = op_idx
    dut.a.value = a
    dut.b.value = b
    await Timer(1, "ns")
    exp = ref_alu(OPS[op_idx], a, b)
    got = dut.y.value.integer
    assert got == exp, f"{OPS[op_idx]}(0x{a:08x}, 0x{b:08x}) = 0x{got:08x}, expected 0x{exp:08x}"


@cocotb.test()
async def corners(dut):
    for i in range(len(OPS)):
        for a in CORNERS:
            for b in CORNERS:
                await check(dut, i, a, b)


@cocotb.test()
async def random_vectors(dut):
    rng = random.Random(0xA1)
    for i in range(len(OPS)):
        for _ in range(N_RANDOM):
            await check(dut, i, rng.getrandbits(32), rng.getrandbits(32))
    dut._log.info(f"{len(OPS)} ops x {N_RANDOM} random operand pairs: 0 mismatches")
