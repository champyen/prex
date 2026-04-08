/*-
 * Copyright (c) 2009-2010, Richard Pandion
 * Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the author nor the names of any co-contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

/*
 * machdep.c - machine-dependent routines for QEMU virt
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

#include "platform.h"

#ifdef CONFIG_MMU
/*
 * Virtual and physical address mapping
 *
 *      { virtual, physical, size, type }
 */
struct mmumap mmumap_table[] = {
    /* RAM: 0x40000000 (default 256M) */
    {CONFIG_SYSPAGE_BASE, CONFIG_SYSPAGE_PHY_BASE, CONFIG_RAM_SIZE, VMT_RAM},

    /* GIC: 0x08000000 */
    {CONFIG_GIC_DIST_BASE, CONFIG_GIC_DIST_PHY_BASE, 0x10000, VMT_IO},
    {CONFIG_GIC_CPU_BASE, CONFIG_GIC_CPU_PHY_BASE, 0x10000, VMT_IO},
    /* PL011 UART: 0x09000000 */
    {CONFIG_PL011_BASE, CONFIG_PL011_PHY_BASE, 0x1000, VMT_IO},
    /* PL031 RTC: 0x09010000 */
    {CONFIG_PL031_BASE, CONFIG_PL031_PHY_BASE, 0x1000, VMT_IO},
    /* VIRTIO MMIO: 0x0A000000 */
    {CONFIG_VIO_MMIO_BASE, CONFIG_VIO_MMIO_PHY_BASE, 0x4000, VMT_IO},

    {0, 0, 0, 0}};
#endif

/*
 * Idle
 */
void machine_idle(void)
{

    cpu_idle();
}

/*
 * Reset system.
 */
static void machine_reset(void)
{
}

/*
 * Set system power
 */
void machine_powerdown(int state)
{

    splhigh();

    DPRINTF(("Power down machine\n"));

    switch (state) {
    case PWR_OFF:
    case PWR_REBOOT:
        machine_reset();
        /* NOTREACHED */
        break;
    }
}

/*
 * Return pointer to the boot information.
 */
void machine_abort(void)
{

    for (;;)
        cpu_idle();
}

void machine_bootinfo(struct bootinfo** bip)
{

    *bip = (struct bootinfo*)BOOTINFO;
}

/*
 * Machine-dependent startup code
 */
void machine_startup(void)
{

    /*
     * Initialize CPU and basic hardware.
     */
    cpu_init();
#ifdef CONFIG_CACHE
    cache_init();
#endif

    /*
     * Reserve system pages.
     */
    page_reserve(CONFIG_SYSPAGE_PHY_BASE, SYSPAGESZ);

    /*
     * Setup vector page.
     */
    vector_copy(CONFIG_SYSPAGE_PHY_BASE);
    #ifndef CONFIG_MMU
    // since DRAM start at 0x40000000, we need to use set_vbar for vector table setting
    set_vbar(CONFIG_SYSPAGE_PHY_BASE);
    #endif

#ifdef CONFIG_MMU
    /*
     * Initialize MMU
     */
    mmu_init(mmumap_table);
#endif
}
