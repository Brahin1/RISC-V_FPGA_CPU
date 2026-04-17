// sim_main.cpp - Verilator harness for soc_top
//
// Plusargs:
//   +imem=<file.hex> +dmem=<file.hex>   memory images (read by tcm.sv)
//   +max_cycles=<n>                     timeout (default 50M)
//   +trace=<file>                       retire trace for tb/lockstep/compare.py
//   +vcd=<file>                         waveform dump (build with TRACE=1)
//   +quiet                              don't echo the console
//
// Exit status: 0 = tohost reported pass, 1 = fail code, 2 = timeout.

#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <memory>
#include <string>

#include "Vsoc_top.h"
#include "verilated.h"
#if VM_TRACE
#include "verilated_vcd_c.h"
#endif

static std::string plusarg(const char *name)
{
    const char *m = Verilated::commandArgsPlusMatch(name);
    if (!m || !*m) return "";
    std::string s(m);
    std::string key = std::string("+") + name;
    if (s.compare(0, key.size(), key) != 0) return "";
    s = s.substr(key.size());
    if (!s.empty() && s[0] == '=') s = s.substr(1);
    else if (s.empty()) s = "1";
    return s;
}

int main(int argc, char **argv)
{
    auto ctx = std::make_unique<VerilatedContext>();
    ctx->commandArgs(argc, argv);
    auto top = std::make_unique<Vsoc_top>(ctx.get());

    uint64_t max_cycles = 50'000'000ULL;
    if (auto s = plusarg("max_cycles"); !s.empty()) max_cycles = strtoull(s.c_str(), nullptr, 0);
    bool quiet = !plusarg("quiet").empty();

    FILE *trace = nullptr;
    if (auto s = plusarg("trace"); !s.empty()) {
        trace = fopen(s.c_str(), "w");
        if (!trace) { perror(s.c_str()); return 3; }
    }

#if VM_TRACE
    std::unique_ptr<VerilatedVcdC> vcd;
    if (auto s = plusarg("vcd"); !s.empty()) {
        ctx->traceEverOn(true);
        vcd = std::make_unique<VerilatedVcdC>();
        top->trace(vcd.get(), 99);
        vcd->open(s.c_str());
    }
#endif

    // PS-side ports unused in simulation
    top->imem_a_en = 0; top->imem_a_we = 0; top->imem_a_addr = 0; top->imem_a_wdata = 0;
    top->dmem_a_en = 0; top->dmem_a_we = 0; top->dmem_a_addr = 0; top->dmem_a_wdata = 0;
    top->con_pop = 0;

    uint64_t cycle = 0, instret = 0;
    auto tick = [&]() {
        top->clk = 0; top->eval();
#if VM_TRACE
        if (vcd) vcd->dump(2 * cycle);
#endif
        top->clk = 1; top->eval();
#if VM_TRACE
        if (vcd) vcd->dump(2 * cycle + 1);
#endif
        cycle++;
    };

    top->rst_n = 0;
    for (int i = 0; i < 5; i++) tick();
    top->rst_n = 1;
    cycle = 0;

    int status = 2;
    uint32_t tohost = 0;
    while (cycle < max_cycles && !ctx->gotFinish()) {
        top->clk = 0; top->eval();

        // sample outputs for the cycle that is about to complete
        if (top->rvfi_valid) {
            instret++;
            if (trace) {
                fprintf(trace, "%08x %08x %02u %08x %08x %x %08x\n",
                        top->rvfi_pc_rdata, top->rvfi_insn, top->rvfi_rd_addr,
                        top->rvfi_rd_wdata, top->rvfi_mem_addr, top->rvfi_mem_wmask,
                        top->rvfi_mem_wdata);
            }
        }
        if (top->console_valid && !quiet) {
            fputc(top->console_byte, stdout);
            fflush(stdout);
        }
        bool done = top->tohost_valid;
        tohost = top->tohost_data;

#if VM_TRACE
        if (vcd) vcd->dump(2 * cycle);
#endif
        top->clk = 1; top->eval();
#if VM_TRACE
        if (vcd) vcd->dump(2 * cycle + 1);
#endif
        cycle++;
        if (done) { status = (tohost == 1) ? 0 : 1; break; }
    }

    if (status == 0)      fprintf(stderr, "[sim] PASS  cycles=%llu instret=%llu\n",
                                  (unsigned long long)cycle, (unsigned long long)instret);
    else if (status == 1) fprintf(stderr, "[sim] FAIL  code=%u (tohost=0x%08x) cycles=%llu\n",
                                  tohost >> 1, tohost, (unsigned long long)cycle);
    else                  fprintf(stderr, "[sim] TIMEOUT after %llu cycles\n",
                                  (unsigned long long)cycle);

    if (trace) fclose(trace);
#if VM_TRACE
    if (vcd) vcd->close();
#endif
    top->final();
    return status;
}
