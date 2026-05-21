// timer_irq.c - machine timer interrupt test
//
// Arms mtimecmp, enables MTIE + MIE and runs a loop that keeps a running
// checksum in registers while interrupts land at arbitrary points in it. The
// handler re-arms the timer. Passes if all interrupts arrive with the right
// mcause and the checksum (which interrupts must not disturb) is intact.

#include "console.h"

#define N_IRQS   20
#define PERIOD   397          // cycles, odd so the interrupt point drifts

static volatile uint32_t irq_count;
static volatile uint32_t bad_cause;

static void arm(uint32_t delta)
{
    uint32_t now = MTIME_LO;
    MTIMECMP_HI = 0xFFFFFFFF;           // avoid a spurious match while updating
    MTIMECMP_LO = now + delta;
    MTIMECMP_HI = MTIME_HI;
}

void trap_handler(uint32_t mcause, uint32_t mepc)
{
    (void)mepc;
    if (mcause != 0x80000007u) {
        bad_cause = mcause;
        MTIMECMP_HI = 0xFFFFFFFF;
        return;
    }
    irq_count++;
    if (irq_count < N_IRQS) arm(PERIOD);
    else                    MTIMECMP_HI = 0xFFFFFFFF;  // disarm
}

int main(void)
{
    uint32_t sum = 0, expect = 0;

    arm(PERIOD);
    __asm__ volatile ("csrs mie, %0" :: "r"(1u << 7));       // MTIE
    __asm__ volatile ("csrs mstatus, %0" :: "r"(1u << 3));   // MIE

    uint32_t i = 0;
    while (irq_count < N_IRQS && !bad_cause) {
        sum = sum * 33u + (i ^ (i >> 3));
        expect = expect * 33u + (i ^ (i >> 3));
        i++;
        if (i > 1000000) break;
    }
    __asm__ volatile ("csrc mstatus, %0" :: "r"(1u << 3));

    con_puts("timer_irq: ");
    con_putdec(irq_count);
    con_puts(" interrupts, ");
    con_putdec(i);
    con_puts(" loop iterations\n");

    if (bad_cause)          return 3;
    if (irq_count != N_IRQS) return 4;
    if (sum != expect)      return 5;
    return 0;
}
