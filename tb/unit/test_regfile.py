"""Register file: x0 stays zero, write-through on same-cycle read, random traffic
against a Python model."""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, Timer


async def setup(dut):
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())
    dut.we.value = 0
    dut.wa.value = 0
    dut.wd.value = 0
    dut.ra1.value = 0
    dut.ra2.value = 0
    await RisingEdge(dut.clk)


@cocotb.test()
async def x0_is_zero(dut):
    await setup(dut)
    dut.we.value, dut.wa.value, dut.wd.value = 1, 0, 0xDEADBEEF
    dut.ra1.value, dut.ra2.value = 0, 0
    await ReadOnly()
    assert dut.rd1.value.integer == 0, "x0 forwarded through the write-through path"
    await RisingEdge(dut.clk)
    dut.we.value = 0
    await ReadOnly()
    assert dut.rd1.value.integer == 0 and dut.rd2.value.integer == 0


@cocotb.test()
async def write_through(dut):
    await setup(dut)
    dut.we.value, dut.wa.value, dut.wd.value = 1, 5, 0x12345678
    dut.ra1.value, dut.ra2.value = 5, 6
    await ReadOnly()
    assert dut.rd1.value.integer == 0x12345678, "same-cycle read did not see the write"
    await RisingEdge(dut.clk)
    dut.we.value = 0
    await ReadOnly()
    assert dut.rd1.value.integer == 0x12345678


@cocotb.test()
async def random_traffic(dut):
    await setup(dut)
    rng = random.Random(7)
    model = [0] * 32
    for _ in range(5000):
        we = rng.random() < 0.7
        wa = rng.randrange(32)
        wd = rng.getrandbits(32)
        r1, r2 = rng.randrange(32), rng.randrange(32)
        dut.we.value, dut.wa.value, dut.wd.value = int(we), wa, wd
        dut.ra1.value, dut.ra2.value = r1, r2
        await Timer(1, "ns")
        for r, port in ((r1, dut.rd1), (r2, dut.rd2)):
            exp = 0 if r == 0 else (wd if (we and wa == r) else model[r])
            assert port.value.integer == exp, f"x{r}: got 0x{port.value.integer:08x} exp 0x{exp:08x}"
        await RisingEdge(dut.clk)
        if we and wa:
            model[wa] = wd
