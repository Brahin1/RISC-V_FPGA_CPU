// hello.c - first program: console output and a quick sanity check of M ops
#include "console.h"

int main(void)
{
    con_puts("hello from rv32im\n");

    volatile int a = 1234567, b = -89;
    int p = a * b, q = a / b, r = a % b;
    if (p != -109876463 || q != -13871 || r != 48)
        return 2;

    con_puts("cycles=");  con_putdec(rdcycle());
    con_puts(" instret="); con_putdec(rdinstret());
    con_putc('\n');
    return 0;
}
