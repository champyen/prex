/*-
 * Copyright (c) 2009, Richard Pandion
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

#include <sys/param.h>
#include <sys/bootinfo.h>
#include <boot.h>

#define SDRC_BASE 0x6D000000
#define SDRC_MCFG_0 (*(volatile uint32_t*)(SDRC_BASE + 0x80))
#define SDRC_MCFG_1 (*(volatile uint32_t*)(SDRC_BASE + 0xB0))

/*
 * Setup boot information.
 */
static void
bootinfo_init(void)
{
    struct bootinfo* bi = bootinfo;

    uint32_t size0 = 0, size1 = 0;

    /*
	 * Screen size
	 */
    bi->video.text_x = 80;
    bi->video.text_y = 25;

    /*
	 * SDRAM - Autodetect
	 * Should be 128 MB on RevA/B and 256MB on RevC
	 */

    size0 = SDRC_MCFG_0 >> 8;
    size0 &= 0x3FF; /* get bank size in 2-MB chunks */
    size0 *= 0x200000; /* compute size */
    size1 = SDRC_MCFG_1 >> 8;
    size1 &= 0x3FF; /* get bank size in 2-MB chunks */
    size1 *= 0x200000; /* compute size */

    bi->ram[0].base = 0x80000000;
    bi->ram[0].size = size0;
    bi->ram[0].type = MT_USABLE;
    if (size1 > 0) {
        /*
	 	* Normally, we are started from U-Boot and
	 	* it should have made memory banks contiguous...		 	 	
	 	*/
        bi->ram[1].base = 0x80000000 + size0;
        bi->ram[1].size = size1;
        bi->ram[1].type = MT_USABLE;
        bi->nr_rams = 2;
    } else {
        bi->nr_rams = 1;
    }
}

void startup(void)
{

    bootinfo_init();
}
