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
int hal_cpu_start(uint32_t cpuid, paddr_t entry)
{
#ifdef CONFIG_SMODE
    struct sbiret ret;
    /* SBI HSM HART_START: ext=0x48534D, fid=0, hartid, start_addr, opaque */
    ret = sbi_call(SBI_EXT_HSM, SBI_HSM_HART_START, (long)cpuid, (long)entry, 0);
    return (int)ret.error;
#else
    /* Bare-metal start logic (e.g., Pico 2 SIO) would go here */
    return -1;
#endif
}

/*
 * Send IPI to other CPUs.
 */
void hal_cpu_send_ipi(uint32_t mask, uint32_t vector)
{
#ifdef CONFIG_SMODE
    if (mask == 0) {
        uint32_t cpuid = hal_cpu_id();
        mask = ((1 << CONFIG_SMP_NCPUS) - 1) & ~(1 << cpuid);
    }
    sbi_call(SBI_EXT_IPI, 0, (long)mask, 0, 0);
#else
    if (mask == 0) {
        uint32_t cpuid = hal_cpu_id();
        mask = ((1 << CONFIG_SMP_NCPUS) - 1) & ~(1 << cpuid);
    }
    for (int i = 0; i < CONFIG_SMP_NCPUS; i++) {
        if (mask & (1 << i)) {
            *(volatile uint32_t*)(CONFIG_CLINT_PHY_BASE + i * 4) = 1;
        }
    }
#endif
}

/*
 * Initialize interrupt controller for secondary CPU.
 */


/*
 * Initialize timer for secondary CPU.
 */
void clock_ap_init(void)
{
    /* To be implemented in Stage 4 */
}

#endif
