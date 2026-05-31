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

void machine_idle(void)
{
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
    volatile uint32_t *vtor = (volatile uint32_t *)0xE000ED08;
    extern void kernel_start(void);
    *vtor = (uint32_t)kernel_start;
}
