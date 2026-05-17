/*
 * cpu.c - CPU dependent routines for RISC-V
 */

#include <kernel.h>
#include <hal.h>
#include <cpufunc.h>
#include <context.h>

void splx(int s)
{
    if (s & 0x2) /* SIE is bit 1 */
        splon();
    else
        sploff();
}

int spl0(void)
{
    int s = get_status();
    splon();
    return s;
}

int splhigh(void)
{
    int s = get_status();
    sploff();
    return s;
}

void cpu_init(void)
{
}

