/*-
 * Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
 * All rights reserved.
 */

#include <machine/syspage.h>
#include <sys/power.h>
#include <sys/bootinfo.h>
#include <kernel.h>
#include <page.h>
#include <cpu.h>
#include <locore.h>

#define SAU_CTRL  (*(volatile uint32_t*)0xE000EDD0)
#define SAU_RNR   (*(volatile uint32_t*)0xE000EDD8)
#define SAU_RBAR  (*(volatile uint32_t*)0xE000EDDC)
#define SAU_RLAR  (*(volatile uint32_t*)0xE000EDE0)

static void sau_init(void)
{
    /* 1. Disable SAU temporarily */
    SAU_CTRL &= ~1;

    /* 2. Configure Region 0: Non-Secure User Tasks Execution (QSPI Flash Non-Secure Alias) */
    SAU_RNR = 0;
    SAU_RBAR = 0x00020000 & 0xFFFFFFE0;
    SAU_RLAR = (0x007FFFFF & 0xFFFFFFE0) | 1; /* Enable, Non-secure */

    /* 3. Configure Region 1: Non-Secure Callable (NSC) Veneers in QSPI Flash */
    SAU_RNR = 1;
    SAU_RBAR = 0x1001F000 & 0xFFFFFFE0;
    SAU_RLAR = (0x1001FFFF & 0xFFFFFFE0) | 3; /* Enable, Non-secure Callable (NSC) */

    /* 4. Configure Region 2: Non-Secure RAM (System SRAM Non-Secure Alias) */
    SAU_RNR = 2;
    SAU_RBAR = 0x20020000 & 0xFFFFFFE0;       /* Start at 128KB offset (1:3 split) */
    SAU_RLAR = (0x2007FFFF & 0xFFFFFFE0) | 1; /* Enable, Non-secure */

    /* 5. Enable SAU - DISABLED for debugging */
    /* SAU_CTRL |= 1; */
    __asm__ volatile("dsb" : : : "memory");
    __asm__ volatile("isb" : : : "memory");
}

void machine_idle(void)
{
    uint32_t ipsr;
    __asm__ volatile("mrs %0, ipsr" : "=r"(ipsr));
    if (ipsr != 0) {
        /* We are in Handler Mode! Let's do an exception return to Thread Mode. */
        __asm__ volatile(
            "mov     r0, sp\n"
            "sub     r0, r0, #32\n"       /* Allocate dummy exception frame */
            "ldr     r1, =1f\n"           /* pc = label 1 */
            "str     r1, [r0, #24]\n"
            "ldr     r1, =0x01000000\n"   /* xPSR = Thumb */
            "str     r1, [r0, #28]\n"
            "mov     sp, r0\n"
            "ldr     lr, =0xFFFFFFF9\n"   /* EXC_RETURN to Thread Mode using MSP */
            "bx      lr\n"                /* Exception return! */
            "1:\n"                        /* We resume here in Thread Mode! */
            : : : "r0", "r1", "lr", "memory"
        );
    }
    __asm__ volatile("wfi");
}

static void machine_reset(void)
{
    volatile uint32_t *aircr = (volatile uint32_t *)0xE000ED0C;
    *aircr = 0x05FA0004;
}

void machine_powerdown(int state)
{
    splhigh();
    switch (state) {
    case PWR_OFF:
    case PWR_REBOOT:
        machine_reset();
        break;
    }
    for (;;) __asm__ volatile("wfi");
}

void machine_abort(void)
{
    for (;;) __asm__ volatile("wfi");
}

void machine_bootinfo(struct bootinfo** bip)
{
    *bip = (struct bootinfo*)BOOTINFO;
}

void machine_startup(void)
{
    cpu_init();
    page_reserve(CONFIG_SYSPAGE_PHY_BASE, SYSPAGESZ);
    sau_init();
    volatile uint32_t *vtor = (volatile uint32_t *)0xE000ED08;
    extern void kernel_start(void);
    *vtor = (uint32_t)kernel_start;
    __asm__ volatile("dsb" : : : "memory");
    __asm__ volatile("isb" : : : "memory");
}
