// sc_main.cpp - Verilator harness for the single-cycle reference core
#include <cstdio>
#include <memory>
#include "Vsc_tb.h"
#include "verilated.h"

int main(int argc, char **argv)
{
    auto ctx = std::make_unique<VerilatedContext>();
    ctx->commandArgs(argc, argv);
    auto top = std::make_unique<Vsc_tb>(ctx.get());

    top->rst_n = 0;
    for (int i = 0; i < 4; i++) { top->clk = 0; top->eval(); top->clk = 1; top->eval(); }
    top->rst_n = 1;

    for (unsigned long cyc = 0; cyc < 20'000'000UL; cyc++) {
        top->clk = 0; top->eval();
        if (top->console_valid) putchar(top->console_byte);
        if (top->halted) { fprintf(stderr, "[sc] HALT (unsupported instruction) at cycle %lu\n", cyc); return 3; }
        if (top->done) {
            bool pass = top->tohost == 1;
            fprintf(stderr, "[sc] %s cycles=%lu\n", pass ? "PASS" : "FAIL", cyc + 1);
            return pass ? 0 : 1;
        }
        top->clk = 1; top->eval();
    }
    fprintf(stderr, "[sc] TIMEOUT\n");
    return 2;
}
