/*
 * machdep.c - machine-dependent routines for RISC-V QEMU virt
 */

#include <machine/syspage.h>
#include <sys/power.h>
#include <sys/bootinfo.h>
#include <kernel.h>
#include <page.h>
#include <mmu.h>
#include <cpu.h>
#include <cpufunc.h>
#include <locore.h>

void machine_idle(void)
{
    cpu_idle();
}

void machine_powerdown(int state)
{
    splhigh();
    for (;;)
        cpu_idle();
}

void machine_abort(void)
{
    for (;;)
        cpu_idle();
}

void machine_bootinfo(struct bootinfo** bip)
{
    *bip = (struct bootinfo*)BOOTINFO;
}

void machine_startup(void)
{
    cpu_init();
    page_reserve(CONFIG_SYSPAGE_PHY_BASE, SYSPAGESZ);
}
