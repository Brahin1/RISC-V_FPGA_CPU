/*
 * ee_printf.c - small printf for CoreMark output on the MMIO console.
 * Supports %d %i %u %x %X %s %c %% with optional '0' flag, width and 'l'.
 */
#include <stdarg.h>
#include "coremark.h"

#define CONSOLE (*(volatile unsigned int *)0x10000008u)

static void out(char c) { CONSOLE = (unsigned char)c; }

static int put_num(unsigned long long v, int base, int neg, int width, char pad, int upper)
{
    const char *dig = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    char buf[24];
    int n = 0, cnt = 0;
    do { buf[n++] = dig[v % base]; v /= base; } while (v);
    if (neg) {
        if (pad == '0') { out('-'); cnt++; width--; }
        else buf[n++] = '-';
    }
    while (width-- > n) { out(pad); cnt++; }
    while (n) { out(buf[--n]); cnt++; }
    return cnt;
}

int ee_printf(const char *fmt, ...)
{
    va_list ap;
    int cnt = 0;
    va_start(ap, fmt);
    for (; *fmt; fmt++) {
        if (*fmt != '%') { out(*fmt); cnt++; continue; }
        fmt++;
        char pad = ' ';
        int width = 0, lng = 0;
        if (*fmt == '0') { pad = '0'; fmt++; }
        while (*fmt >= '0' && *fmt <= '9') width = width * 10 + (*fmt++ - '0');
        while (*fmt == 'l') { lng++; fmt++; }
        switch (*fmt) {
        case 'd': case 'i': {
            long long v = lng > 1 ? va_arg(ap, long long) : (lng ? va_arg(ap, long) : va_arg(ap, int));
            cnt += put_num(v < 0 ? -(unsigned long long)v : (unsigned long long)v, 10, v < 0, width, pad, 0);
            break;
        }
        case 'u': case 'x': case 'X': {
            unsigned long long v = lng > 1 ? va_arg(ap, unsigned long long)
                                 : (lng ? va_arg(ap, unsigned long) : va_arg(ap, unsigned int));
            cnt += put_num(v, *fmt == 'u' ? 10 : 16, 0, width, pad, *fmt == 'X');
            break;
        }
        case 's': {
            const char *s = va_arg(ap, const char *);
            while (*s) { out(*s++); cnt++; }
            break;
        }
        case 'c': out((char)va_arg(ap, int)); cnt++; break;
        case '%': out('%'); cnt++; break;
        default:  out('%'); out(*fmt); cnt += 2; break;
        }
    }
    va_end(ap);
    return cnt;
}
