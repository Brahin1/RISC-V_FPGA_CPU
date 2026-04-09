"""M-extension unit: MUL pipeline (result one cycle after issue) and the
iterative divider, including the spec corner cases."""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, FallingEdge

from rv32iss import muldiv as ref

OPS = ["mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu"]   # funct3 order
CORNERS = [0, 1, 0xFFFFFFFF, 0x80000000, 0x7FFFFFFF, 2, 0xFFFFFFFE, 0x12345678]


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())
    dut.rst_n.value = 0
    for s in (dut.ex_valid, dut.ex_is_mul, dut.ex_is_div, dut.ex_funct3, dut.ex_a, dut.ex_b,
              dut.ex_advance, dut.flush):
        s.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await FallingEdge(dut.clk)


async def do_mul(dut, f3, a, b):
    dut.ex_valid.value, dut.ex_is_mul.value, dut.ex_is_div.value = 1, 1, 0
    dut.ex_funct3.value, dut.ex_a.value, dut.ex_b.value = f3, a, b
    dut.ex_advance.value = 1
    await FallingEdge(dut.clk)                 # instruction is now "in MEM"
    dut.ex_valid.value, dut.ex_is_mul.value = 0, 0
    await ReadOnly()
    got = dut.mul_result.value.integer
    await FallingEdge(dut.clk)
    return got


async def do_div(dut, f3, a, b):
    dut.ex_valid.value, dut.ex_is_mul.value, dut.ex_is_div.value = 1, 0, 1
    dut.ex_funct3.value, dut.ex_a.value, dut.ex_b.value = f3, a, b
    cycles = 0
    while True:
        await ReadOnly()
        stall = dut.div_stall.value.integer
        res = dut.div_result.value.integer
        await FallingEdge(dut.clk)
        dut.ex_advance.value = int(not stall)
        if not stall:
            break
        cycles += 1
        assert cycles < 40, "divider never finished"
    await RisingEdge(dut.clk)                  # advance edge clears 'done'
    await FallingEdge(dut.clk)
    dut.ex_valid.value, dut.ex_is_div.value, dut.ex_advance.value = 0, 0, 0
    return res, cycles


@cocotb.test()
async def mul_corners_and_random(dut):
    await reset(dut)
    rng = random.Random(3)
    vecs = [(a, b) for a in CORNERS for b in CORNERS] + \
           [(rng.getrandbits(32), rng.getrandbits(32)) for _ in range(2500)]
    for f3 in range(4):
        for a, b in vecs:
            got = await do_mul(dut, f3, a, b)
            exp = ref(OPS[f3], a, b)
            assert got == exp, f"{OPS[f3]}(0x{a:08x}, 0x{b:08x}) = 0x{got:08x}, exp 0x{exp:08x}"


@cocotb.test()
async def div_corners(dut):
    await reset(dut)
    for f3 in range(4, 8):
        for a in CORNERS:
            for b in CORNERS:
                got, _ = await do_div(dut, f3, a, b)
                exp = ref(OPS[f3], a, b)
                assert got == exp, f"{OPS[f3]}(0x{a:08x}, 0x{b:08x}) = 0x{got:08x}, exp 0x{exp:08x}"


@cocotb.test()
async def div_random_and_latency(dut):
    await reset(dut)
    rng = random.Random(11)
    lat = set()
    for _ in range(600):
        f3 = rng.randrange(4, 8)
        a, b = rng.getrandbits(32), rng.getrandbits(rng.choice([4, 16, 32]))
        got, cyc = await do_div(dut, f3, a, b)
        exp = ref(OPS[f3], a, b)
        assert got == exp, f"{OPS[f3]}(0x{a:08x}, 0x{b:08x}) = 0x{got:08x}, exp 0x{exp:08x}"
        if b:
            lat.add(cyc)
    dut._log.info(f"divider stall cycles (b != 0): {sorted(lat)}")
    assert lat == {33}


@cocotb.test()
async def div_flush(dut):
    """A flush in the middle of a divide must leave the unit idle and ready."""
    await reset(dut)
    dut.ex_valid.value, dut.ex_is_div.value, dut.ex_funct3.value = 1, 1, 4
    dut.ex_a.value, dut.ex_b.value = 1000, 7
    for _ in range(5):
        await FallingEdge(dut.clk)
    dut.flush.value = 1
    dut.ex_valid.value = 0
    await FallingEdge(dut.clk)
    dut.flush.value = 0
    got, _ = await do_div(dut, 5, 100, 9)
    assert got == 11
