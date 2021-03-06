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
 * locore_machdep.S for TI OMAP3 SoC
 */

#include <conf/config.h>
#include <machine/asm.h>

	.section ".text","ax"
	.code 32

/*
 * Data synchronization barrier for MPU INTC
 */
ENTRY(mpu_intc_sync)
	mov	r0, #0
	mcr	p15, 0, r0, c7, c10, 4
	mov	pc, lr

/*
 * Default exception vectors at 0x4020ffc8 (SRAM)
 * Use VBAR control register to change it
 */ 
ENTRY(set_vbar)
	mcr	p15, 0, r0, c12, c0, 0
	mov	pc, lr

/*
 * Reset system.
 */
ENTRY(machine_reset)
	/*
	 * Set MMU off...
	 */
	mrc	p15, 0, r0, c1, c0, 0
	bic	r0, r0, #0x01
	mcr	p15, 0, r0, c1, c0, 0
	
	/*
	 * ...then use control register to initiate reset command
	 */
	ldr	r0, =0x48307250
	ldr	r1,	=0x02
	str	r1,[r0]
	/* NOTREACHED */
1:
	b	1b

	.end
