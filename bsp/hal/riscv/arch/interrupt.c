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

#define PLIC_BASE CONFIG_PLIC_BASE

/* 
 * PLIC Registers for QEMU Virt (RV32)
 * On QEMU Virt, S-mode context for hart 0 is Context 1.
 * M-mode is Context 0.
 */
#define PLIC_PRIORITY(irq)   (*(volatile uint32_t*)(PLIC_BASE + 4 * (irq)))
/* S-mode Hart 0 Enable: 0x2000 + HartID * 0x100 + 0x80 (for S-mode) */
#define PLIC_S_ENABLE(irq)   (*(volatile uint32_t*)(PLIC_BASE + 0x2080 + ((irq) / 32) * 4))
/* S-mode Hart 0 Threshold/Claim: 0x200000 + HartID * 0x2000 + 0x1000 (for S-mode) */
#define PLIC_S_THRESHOLD     (*(volatile uint32_t*)(PLIC_BASE + 0x201000))
#define PLIC_S_CLAIM         (*(volatile uint32_t*)(PLIC_BASE + 0x201004))

void interrupt_unmask(int vector, int level)
{
    if (vector > 0 && vector < 1024) {
        PLIC_PRIORITY(vector) = 1;
        PLIC_S_ENABLE(vector) |= (1 << (vector % 32));
    }
}

void interrupt_mask(int vector)
{
    if (vector > 0 && vector < 1024) {
        PLIC_S_ENABLE(vector) &= ~(1 << (vector % 32));
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

    sched_lock();

    if (cause == 9) {
        /* Supervisor External Interrupt */
        irq = PLIC_S_CLAIM;
        if (irq) {
            irq_handler(irq);
            PLIC_S_CLAIM = irq;
        }
    } else if (cause == 5) {
        /* Supervisor Timer Interrupt */
        irq_handler(0);
    }

    sched_unlock();
}

void interrupt_init(void)
{
    int i;
    
    /* Disable all interrupts and set priority to 0 */
    for (i = 1; i < 1024; i++) {
        PLIC_PRIORITY(i) = 0;
    }
    /* Disable enables for context 1 (S-mode) */
    for (i = 0; i < (1024 + 31) / 32; i++) {
        *(volatile uint32_t*)(PLIC_BASE + 0x2080 + i * 4) = 0;
    }
    
    /* Set threshold to 0 to allow all */
    PLIC_S_THRESHOLD = 0;

    /* Enable Timer and External interrupts in sie */
    uint32_t sie = 0x220; /* STIE (bit 5) and SEIE (bit 9) */
    __asm__ volatile("csrw sie, %0" : : "r"(sie));
}
