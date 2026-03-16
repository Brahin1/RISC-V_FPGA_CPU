// console.h - minimal console output through the MMIO console register
#ifndef CONSOLE_H
#define CONSOLE_H

#include <stdint.h>

#define MMIO_BASE     0x10000000u
#define REG32(off)    (*(volatile uint32_t *)(MMIO_BASE + (off)))
#define CONSOLE_REG   REG32(0x04)
#define MTIME_LO      REG32(0x08)
#define MTIME_HI      REG32(0x0C)
#define MTIMECMP_LO   REG32(0x10)
#define MTIMECMP_HI   REG32(0x14)
#define LED_REG       REG32(0x18)

void con_putc(char c);
void con_puts(const char *s);
void con_puthex(uint32_t v);
void con_putdec(uint32_t v);

static inline uint32_t rdcycle(void)   { uint32_t v; __asm__ volatile ("csrr %0, mcycle"   : "=r"(v)); return v; }
static inline uint32_t rdinstret(void) { uint32_t v; __asm__ volatile ("csrr %0, minstret" : "=r"(v)); return v; }

#endif
