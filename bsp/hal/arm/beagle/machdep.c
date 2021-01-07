/*-
 * Copyright (c) 2009-2010, Richard Pandion
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
 * machdep.c - machine-dependent routines for Beagle Board
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
    /*
	 * Q1 : 
	 *	Boot ROM			(112 KB)
	 *	SRAM				( 64 KB)
	 *	L4 Interconnects	( 17 MB)
	 * 	SGX					( 64 KB)
	 *	L4 Emulation		(  8 MB)
	 *	IVA2.2 SS			( 48 MB)
	 *	L3 control regs		( 16 MB)
	 *	SMS, SRDC, GPMC
	 *	  control regs		( 48 MB)
	 */
    { 0xa0000000, 0x40000000, 0x0001C000, VMT_ROM },
    { 0xa0200000, 0x40200000, 0x00010000, VMT_RAM },
    { 0xa8000000, 0x48000000, 0x01100000, VMT_IO },
    { 0xb0000000, 0x50000000, 0x00010000, VMT_IO },
    { 0xb4000000, 0x54000000, 0x00800000, VMT_IO },
    { 0xbC000000, 0x5C000000, 0x03000000, VMT_IO },
    { 0xc8000000, 0x68000000, 0x01000000, VMT_IO },
    { 0xcC000000, 0x6C000000, 0x03000000, VMT_IO },

    /*
	 * Q2: SDRAM (512 MB)
	 * Although Q2 is 1 GB in size we only map 512 MB
	 * as this is the max ram size on the Beagle Board
	 */
    { 0x80000000, 0x80000000, 0x20000000, VMT_RAM },

    { 0, 0, 0, 0 }
};
#endif

/*
 * Idle
 */
void machine_idle(void)
{

    cpu_idle();
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
        for (;;)
            cpu_idle();
        /* NOTREACHED */
        break;
    case PWR_REBOOT:
        machine_reset();
        /* NOTREACHED */
        break;
    }
}

/*
 * Return pointer to the boot information.
 */
void machine_bootinfo(struct bootinfo** bip)
{

    *bip = (struct bootinfo*)BOOTINFO;
}

void machine_abort(void)
{

    for (;;)
        cpu_idle();
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
    cache_init();

    /*
	 * Reserve system pages.
	 */
    page_reserve(kvtop(SYSPAGE), SYSPAGESZ);

    /*
	 * Setup vector page.
	 */
    vector_copy((vaddr_t)ptokv(CONFIG_ARM_VECTORS));
    set_vbar((vaddr_t)ptokv(CONFIG_ARM_VECTORS));

#ifdef CONFIG_MMU
    /*
	 * Initialize MMU
	 */
    mmu_init(mmumap_table);
#endif
}
