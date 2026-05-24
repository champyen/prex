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
#ifdef CONFIG_SMODE
    /* 
     * SBI IPI Extension (0x735049), Function 0: SEND_IPI
     * a0 = hart_mask, a1 = hart_mask_base
     * If mask is 0, it means all other CPUs in Prex context.
     * We pass mask as a0 and 0 as a1 to target specific harts.
     */
    sbi_call(SBI_EXT_IPI, 0, mask, 0, 0);
#else
    /* Bare-metal CLINT MSIP write would go here */
#endif
}

/*
 * Initialize interrupt controller for secondary CPU.
 */
void interrupt_cpu_init(void)
{
    /* 
     * Standard RISC-V interrupt setup.
     * Specific PLIC context setup is handled in interrupt.c
     */
    extern void plic_cpu_init(void);
    plic_cpu_init();
}

/*
 * Initialize timer for secondary CPU.
 */
void clock_ap_init(void)
{
    /* To be implemented in Stage 4 */
}

#endif
