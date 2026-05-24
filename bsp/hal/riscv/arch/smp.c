/*
 * smp.c - SMP support for RISC-V
 */

#include <kernel.h>
#include <hal.h>
#include <cpufunc.h>
#include <riscv_csr.h>

#include <machine/sbi.h>

#ifdef CONFIG_SMP

/*
 * Start secondary CPU.
 */
int hal_cpu_start(int cpuid, paddr_t entry)
{
#ifdef CONFIG_SMODE
    struct sbiret ret;
    /* SBI HSM HART_START: ext=0x48534D, fid=0, hartid, start_addr, opaque */
    ret = sbi_call(SBI_EXT_HSM, SBI_HSM_HART_START, cpuid, (long)entry, 0);
    return (int)ret.error;
#else
    /* Bare-metal start logic (e.g., Pico 2 SIO) would go here */
    return -1;
#endif
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
