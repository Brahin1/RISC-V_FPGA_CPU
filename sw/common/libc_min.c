// libc_min.c - the handful of libc routines GCC may emit calls to
#include <stddef.h>
#include <stdint.h>

void *memcpy(void *dst, const void *src, size_t n)
{
    uint8_t *d = dst;
    const uint8_t *s = src;
    if ((((uintptr_t)d | (uintptr_t)s | n) & 3) == 0) {
        uint32_t *dw = (uint32_t *)d;
        const uint32_t *sw = (const uint32_t *)s;
        for (size_t i = 0; i < n / 4; i++) dw[i] = sw[i];
        return dst;
    }
    while (n--) *d++ = *s++;
    return dst;
}

void *memset(void *dst, int c, size_t n)
{
    uint8_t *d = dst;
    while (n--) *d++ = (uint8_t)c;
    return dst;
}

int memcmp(const void *a, const void *b, size_t n)
{
    const uint8_t *x = a, *y = b;
    for (; n; n--, x++, y++)
        if (*x != *y) return *x - *y;
    return 0;
}

size_t strlen(const char *s)
{
    size_t n = 0;
    while (s[n]) n++;
    return n;
}
