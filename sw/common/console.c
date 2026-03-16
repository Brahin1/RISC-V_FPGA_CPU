// console.c - console output
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
