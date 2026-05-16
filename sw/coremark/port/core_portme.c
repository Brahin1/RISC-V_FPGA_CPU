/*
 * core_portme.c - CoreMark port for the RV32IM core
 */
#include "coremark.h"
#include "core_portme.h"

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PROFILE_RUN
volatile ee_s32 seed1_volatile = 0x8;
volatile ee_s32 seed2_volatile = 0x8;
volatile ee_s32 seed3_volatile = 0x8;
#endif
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

ee_u32 default_num_contexts = 1;

/* ---- counters ----------------------------------------------------------- */

#define CSRR(name) ({ ee_u32 _v; __asm__ volatile ("csrr %0, " #name : "=r"(_v)); _v; })

typedef struct {
    ee_u32 cycles, instret;
    ee_u32 hpm[6];
} snapshot_t;

static snapshot_t t_start, t_stop;

static inline void snap(snapshot_t *s)
{
    s->hpm[0]  = CSRR(mhpmcounter3);
    s->hpm[1]  = CSRR(mhpmcounter4);
    s->hpm[2]  = CSRR(mhpmcounter5);
    s->hpm[3]  = CSRR(mhpmcounter6);
    s->hpm[4]  = CSRR(mhpmcounter7);
    s->hpm[5]  = CSRR(mhpmcounter8);
    s->instret = CSRR(minstret);
    s->cycles  = CSRR(mcycle);
}

void start_time(void) { snap(&t_start); }
void stop_time(void)  { snap(&t_stop); }

CORE_TICKS get_time(void) { return t_stop.cycles - t_start.cycles; }

secs_ret time_in_secs(CORE_TICKS ticks) { return ticks / CPU_HZ; }

/* ---- init / fini --------------------------------------------------------- */

void portable_init(core_portable *p, int *argc, char *argv[])
{
    (void)argc; (void)argv;
    if (sizeof(ee_ptr_int) != sizeof(ee_u8 *))
        ee_printf("ERROR! ee_ptr_int must hold a pointer\n");
    if (sizeof(ee_u32) != 4)
        ee_printf("ERROR! ee_u32 must be 32 bits\n");
    p->portable_id = 1;
}

void portable_fini(core_portable *p)
{
    ee_u32 cyc = t_stop.cycles - t_start.cycles;
    ee_u32 ins = t_stop.instret - t_start.instret;
    ee_u32 d[6];
    for (int i = 0; i < 6; i++) d[i] = t_stop.hpm[i] - t_start.hpm[i];

    /* CoreMark/MHz = iterations / (cycles / 1e6), printed with 3 decimals */
    unsigned long long milli = (unsigned long long)ITERATIONS * 1000000000ull / cyc;
    ee_printf("CoreMark/MHz: %u.%03u  (%u iterations, %u cycles)\n",
              (ee_u32)(milli / 1000), (ee_u32)(milli % 1000), (ee_u32)ITERATIONS, cyc);
    ee_printf("PERF cycles=%u instret=%u load_use=%u br_mispredict=%u jmp_redirect=%u "
              "muldiv_stall=%u branches=%u traps=%u\n",
              cyc, ins, d[0], d[1], d[2], d[3], d[4], d[5]);
    p->portable_id = 0;
}
