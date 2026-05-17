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

#include <task.h>
#include <exception.h>

extern struct task kernel_task;

void cpu_init(void)
{
    /* Initialize kernel_task safely */
    kernel_task.handler = EXC_DFL;

    /* Initialize sstatus: Disable FPU (FS=0), Disable interrupts */
    /* FS is bits 13-14. Mask = ~(3 << 13) = 0xffff9fff */
    uint32_t status;
    __asm__ volatile("csrr %0, sstatus" : "=r"(status));
    status &= ~0x6000;
    __asm__ volatile("csrw sstatus, %0" : : "r"(status));
}

