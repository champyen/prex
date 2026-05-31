/*
 * interrupt.c - interrupt handling routines for RISC-V (S-Mode)
 */

#include <sys/ipl.h>
#include <kernel.h>
#include <hal.h>
#include <irq.h>
#include <sched.h>
#include <cpufunc.h>
#include <context.h>
#include <locore.h>
#include <cpu.h>

#include <riscv_csr.h>

#define PLIC_BASE CONFIG_PLIC_BASE

/* 
 * PLIC Registers for QEMU Virt (RV32)
 * On QEMU Virt, Hart H has:
 * - M-mode context at index 2H
 * - S-mode context at index 2H + 1
 */
#define PLIC_PRIORITY(irq)   (*(volatile uint32_t*)(PLIC_BASE + 4 * (irq)))

/* S-mode Context index = 2 * hartid + 1 */
/* M-mode Context index = 2 * hartid */
static inline uint32_t plic_context(uint32_t hartid)
{
#ifdef CONFIG_SMODE
    return 2 * hartid + 1;
#else
    return 2 * hartid;
#endif
}

/* Enable bits for a context: 0x2000 + context * 0x80 */
#define PLIC_ENABLE_BASE(ctx) (PLIC_BASE + 0x2000 + (ctx) * 0x80)
/* Threshold/Claim for a context: 0x200000 + context * 0x1000 */
#define PLIC_THRESHOLD_REG(ctx) (*(volatile uint32_t*)(PLIC_BASE + 0x200000 + (ctx) * 0x1000))
#define PLIC_CLAIM_REG(ctx)     (*(volatile uint32_t*)(PLIC_BASE + 0x200004 + (ctx) * 0x1000))

void interrupt_unmask(int vector, int level)
{
    if (vector > 0 && vector < 1024) {
        PLIC_PRIORITY(vector) = 1;
        uint32_t ctx = plic_context(hal_cpu_id());
        *(volatile uint32_t*)(PLIC_ENABLE_BASE(ctx) + ((vector) / 32) * 4) |= (1 << (vector % 32));
    }
}

void interrupt_mask(int vector)
{
    if (vector > 0 && vector < 1024) {
        uint32_t ctx = plic_context(hal_cpu_id());
        *(volatile uint32_t*)(PLIC_ENABLE_BASE(ctx) + ((vector) / 32) * 4) &= ~(1 << (vector % 32));
    }
}

void interrupt_setup(int vector, int mode)
{
}

void interrupt_handler(void)
{
}

void riscv_irq_handler(uint32_t cause)
{
    int irq;
    uint32_t cpuid = hal_cpu_id();
    uint32_t ctx = plic_context(cpuid);

#ifdef CONFIG_SMODE
    if (cause == 9) {
        /* Supervisor External Interrupt */
        irq = PLIC_CLAIM_REG(ctx);
        if (irq) {
            irq_handler(irq);
            PLIC_CLAIM_REG(ctx) = irq;
        }
    } else if (cause == 5) {
        /* Supervisor Timer Interrupt */
        irq_handler(0);
    } else if (cause == 1) {
        /* Supervisor Software Interrupt (IPI) */
        /* Clear pending software interrupt */
        __asm__ volatile("csrc " STR(CSR_IP) ", %0" : : "r"(0x2));
        irq_handler(IPI_IRQ);
    }
#else
    if (cause == 11) {
        /* Machine External Interrupt */
        irq = PLIC_CLAIM_REG(ctx);
        if (irq) {
            irq_handler(irq);
            PLIC_CLAIM_REG(ctx) = irq;
        }
    } else if (cause == 7) {
        /* Machine Timer Interrupt */
        irq_handler(0);
    } else if (cause == 3) {
        /* Machine Software Interrupt (IPI) */
        /* Clear pending software interrupt */
        *(volatile uint32_t*)(CONFIG_CLINT_PHY_BASE + cpuid * 4) = 0;
        irq_handler(IPI_IRQ);
    }
#endif
}

void interrupt_cpu_init(void)
{
    uint32_t cpuid = hal_cpu_id();
    uint32_t ctx = plic_context(cpuid);
    int i;

    /* Disable enables for this CPU's S-mode context */
    for (i = 0; i < (1024 + 31) / 32; i++) {
        *(volatile uint32_t*)(PLIC_ENABLE_BASE(ctx) + i * 4) = 0;
    }
    
    /* Set threshold to 0 to allow all */
    PLIC_THRESHOLD_REG(ctx) = 0;

    /* Enable External interrupts in CSR_IE. 
     * Timer and Software interrupts are enabled later in clock_init and smp_init. 
     */
    uint32_t ie;
#ifdef CONFIG_SMODE
    ie = 0x200; /* SEIE (bit 9) */
#else
    ie = 0x800; /* MEIE (bit 11) */
#endif
    __asm__ volatile("csrw " STR(CSR_IE) ", %0" : : "r"(ie));
}

void interrupt_init(void)
{
    int i;
    
    /* Disable all interrupts and set priority to 0 (Global) */
    for (i = 1; i < 1024; i++) {
        PLIC_PRIORITY(i) = 0;
    }

    /* Perform per-CPU initialization for BSP */
    interrupt_cpu_init();
}
