// console.c - console output and performance counter dump
#include "console.h"

void con_putc(char c) { CONSOLE_REG = (uint8_t)c; }

void con_puts(const char *s) { while (*s) con_putc(*s++); }

void con_puthex(uint32_t v)
{
    static const char hex[] = "0123456789abcdef";
    for (int i = 28; i >= 0; i -= 4) con_putc(hex[(v >> i) & 0xf]);
}

void con_putdec(uint32_t v)
{
    char buf[11];
    int  n = 0;
    do { buf[n++] = '0' + (v % 10); v /= 10; } while (v);
    while (n) con_putc(buf[--n]);
}

uint64_t rdcycle64(void)
{
    uint32_t hi, lo, hi2;
    do {
        __asm__ volatile ("csrr %0, mcycleh" : "=r"(hi));
        __asm__ volatile ("csrr %0, mcycle"  : "=r"(lo));
        __asm__ volatile ("csrr %0, mcycleh" : "=r"(hi2));
    } while (hi != hi2);
    return ((uint64_t)hi << 32) | lo;
}

uint64_t rdinstret64(void)
{
    uint32_t hi, lo, hi2;
    do {
        __asm__ volatile ("csrr %0, minstreth" : "=r"(hi));
        __asm__ volatile ("csrr %0, minstret"  : "=r"(lo));
        __asm__ volatile ("csrr %0, minstreth" : "=r"(hi2));
    } while (hi != hi2);
    return ((uint64_t)hi << 32) | lo;
}

#define RD_HPM(n) ({ uint32_t _v; __asm__ volatile ("csrr %0, mhpmcounter" #n : "=r"(_v)); _v; })

// Machine-readable line consumed by tools/cpi_report.py
void print_perf_counters(void)
{
    uint32_t c = rdcycle(), i = rdinstret();
    con_puts("PERF cycles=");       con_putdec(c);
    con_puts(" instret=");          con_putdec(i);
    con_puts(" load_use=");         con_putdec(RD_HPM(3));
    con_puts(" br_mispredict=");    con_putdec(RD_HPM(4));
    con_puts(" jmp_redirect=");     con_putdec(RD_HPM(5));
    con_puts(" muldiv_stall=");     con_putdec(RD_HPM(6));
    con_puts(" branches=");         con_putdec(RD_HPM(7));
    con_puts(" traps=");            con_putdec(RD_HPM(8));
    con_putc('\n');
}
