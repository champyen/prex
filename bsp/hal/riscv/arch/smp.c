/*
 * smp.c - SMP support for RISC-V
 */

#include <kernel.h>
#include <hal.h>
#include <cpufunc.h>
#include <riscv_csr.h>

#ifdef CONFIG_SMP

/*
 * Start secondary CPU.
 */
int hal_cpu_start(int cpuid, paddr_t entry)
{
    /* To be implemented in Stage 2 */
    return -1;
}

/*
 * Send IPI to other CPUs.
 */
void hal_cpu_send_ipi(int mask, int vector)
{
    /* To be implemented in Stage 3 */
}

/*
 * Initialize interrupt controller for secondary CPU.
 */
void interrupt_cpu_init(void)
{
    /* To be implemented in Stage 3 */
}

/*
 * Initialize timer for secondary CPU.
 */
void clock_ap_init(void)
{
    /* To be implemented in Stage 4 */
}

#endif
