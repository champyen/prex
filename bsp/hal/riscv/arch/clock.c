/*
 * clock.c - clock routines for RISC-V (Supervisor Mode)
 */

#include <kernel.h>
#include <timer.h>
#include <cpu.h>
#include <irq.h>
#include <hal.h>
#include <machine/sbi.h>
#include <riscv_csr.h>

static uint64_t get_time(void)
{
    uint32_t lo, hi, hi2;
    do {
        __asm__ volatile("rdtimeh %0" : "=r"(hi));
        __asm__ volatile("rdtime %0" : "=r"(lo));
        __asm__ volatile("rdtimeh %0" : "=r"(hi2));
    } while (hi != hi2);
    return ((uint64_t)hi << 32) | lo;
}

static uint32_t clock_freq = 10000000; /* QEMU virt timer frequency (10MHz) */
static uint32_t ticks_per_intr;

static void set_timer(uint64_t next)
{
    sbi_set_timer(next);
}

static int clock_isr(void* arg)
{
    timer_handler();
    set_timer(get_time() + ticks_per_intr);
    return INT_DONE;
}

void clock_init(void)
{
    ticks_per_intr = clock_freq / CONFIG_HZ;

    /* Install ISR */
    /* Prex expects IRQ 0 for system timer */
    irq_attach(0, IPL_CLOCK, 0, &clock_isr, IST_NONE, NULL);

    /* Program first interrupt */
    set_timer(get_time() + ticks_per_intr);

    /* Enable timer interrupt (bit 5/7 in CSR_IE) */
#ifdef CONFIG_SMODE
    __asm__ volatile("csrs " STR(CSR_IE) ", %0" : : "r"(0x20));
#else
    __asm__ volatile("csrs " STR(CSR_IE) ", %0" : : "r"(0x80));
#endif

    /* Enable interrupts globally (bit 1/3 in CSR_STATUS) */
#ifdef CONFIG_SMODE
    __asm__ volatile("csrsi " STR(CSR_STATUS) ", 2");
#else
    __asm__ volatile("csrsi " STR(CSR_STATUS) ", 8");
#endif

    DPRINTF(("Clock rate: %d ticks/sec\n", CONFIG_HZ));
}
