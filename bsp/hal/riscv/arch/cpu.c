/*
 * cpu.c - CPU dependent routines for RISC-V
 */

#include <kernel.h>
#include <machine/syspage.h>
#include <hal.h>
#include <cpufunc.h>
#include <context.h>
#include <riscv_csr.h>

void splx(int s)
{
    curspl = s;
    if (curspl == 0 && irq_nesting == 0)
        splon();
    else
        sploff();
}

int spl0(void)
{
    int s = curspl;
    splon();
    curspl = 0;
    return s;
}

int splhigh(void)
{
    int s = curspl;
    sploff();
    curspl = 15;
    return s;
}

#include <task.h>
#include <exception.h>

#include <cpu.h>

struct riscv_cpu riscv_cpus[RISCV_NCPUS];

extern struct task kernel_task;


void cpu_init(void)
{
    /* Initialize kernel_task safely */
    kernel_task.handler = EXC_DFL;

    /* Initialize status: Disable FPU (FS=0), Disable interrupts */
    /* FS is bits 13-14. Mask = ~(3 << 13) = 0xffff9fff */
    uint32_t status;
    __asm__ volatile("csrr %0, " STR(CSR_STATUS) : "=r"(status));
    status &= ~0x6000;
    __asm__ volatile("csrw " STR(CSR_STATUS) ", %0" : : "r"(status));

    extern struct cpu_control cpu_table[];
    riscv_cpus[0].cpu_control = &cpu_table[0];
}


