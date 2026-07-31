/*-
 * Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
 * All rights reserved.
 */

#include <sys/types.h>
#include <cpu.h>
#include <cpufunc.h>

void cpu_idle(void)
{
    __asm__ volatile("wfi");
}

int get_faultstatus(void)
{
    volatile uint32_t *cfsr = (volatile uint32_t *)0xE000ED28;
    return (int)*cfsr;
}

void* get_faultaddress(void)
{
    volatile uint32_t *bfar = (volatile uint32_t *)0xE000ED38;
    return (void *)*bfar;
}

paddr_t get_ttb(void)
{
    return 0;
}

void set_ttb(paddr_t ttb)
{
}

void switch_ttb(paddr_t ttb)
{
}

void flush_tlb(void)
{
}

void flush_cache(void)
{
}

void set_vbar(vaddr_t vbar)
{
    volatile uint32_t *vtor = (volatile uint32_t *)0xE000ED08;
    *vtor = (uint32_t)vbar;
}

void cpu_barrier(void)
{
    __asm__ volatile("dsb\nisb");
}

uint32_t get_cntfrq(void)
{
    return 0;
}

void set_cntp_tval_reg(uint32_t val)
{
}

void set_cntp_ctl_reg(uint32_t val)
{
}

uint32_t get_cntp_ctl_reg(void)
{
    return 0;
}

uint32_t hal_cpu_id(void)
{
#ifdef CONFIG_SMP
    struct cpu_control *cpu = hal_get_cpu_control();
    if (cpu != NULL) {
        return cpu->cpu_id;
    }
#endif
    return 0;
}

void hal_cpu_send_ipi(uint32_t cpumask, uint32_t vector)
{
    (void)cpumask;
    volatile uint32_t *nvic_ispr = (volatile uint32_t *)(0xE000E200 + (vector / 32) * 4);
    *nvic_ispr = (1 << (vector % 32));
    __asm__ volatile("dsb\nisb" : : : "memory");
}




